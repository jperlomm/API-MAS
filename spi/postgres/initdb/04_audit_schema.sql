-- SPI Phase 7 Schema Migration: Carrier-Class Audit Log & Traceability
-- Author: Antigravity AI & ISP Network Architecture Team

-- ----------------------------------------------------
-- 1. INDICES RÁPIDOS DE CONTROL (PREVENCIÓN DE BLOQUEOS)
-- ----------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_servicios_clientes_ip_cm ON admin.servicios_clientes (ip_cm);
CREATE INDEX IF NOT EXISTS idx_servicios_clientes_ip_cpe ON admin.servicios_clientes (ip_cpe);

-- ----------------------------------------------------
-- 2. HISTORIAL DE LEASES IP (TRAZABILIDAD DHCP LEGAL)
-- ----------------------------------------------------
CREATE TABLE IF NOT EXISTS admin.historial_leases_ip (
    id BIGSERIAL PRIMARY KEY,
    ip INET NOT NULL,
    mac MACADDR NOT NULL,
    id_cliente INT REFERENCES admin.clientes(id) ON DELETE SET NULL,
    id_servicio INT REFERENCES admin.servicios_clientes(id) ON DELETE SET NULL,
    fecha_desde TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_hasta TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_historial_ip_rango ON admin.historial_leases_ip (ip, fecha_desde, fecha_hasta);
CREATE INDEX IF NOT EXISTS idx_historial_mac_rango ON admin.historial_leases_ip (mac, fecha_desde, fecha_hasta);
CREATE INDEX IF NOT EXISTS idx_hist_leases_activos ON admin.historial_leases_ip (ip) WHERE (fecha_hasta IS NULL);

-- ----------------------------------------------------
-- 3. HISTORIAL DE EQUIPAMIENTO (CICLO DE VIDA DE HARDWARE)
-- ----------------------------------------------------
CREATE TABLE IF NOT EXISTS admin.historial_equipos_clientes (
    id SERIAL PRIMARY KEY,
    id_equipo INT NOT NULL REFERENCES admin.equipos(id) ON DELETE CASCADE,
    id_cliente INT NOT NULL REFERENCES admin.clientes(id) ON DELETE CASCADE,
    id_servicio INT REFERENCES admin.servicios_clientes(id) ON DELETE SET NULL,
    fecha_entrega TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_devolucion TIMESTAMP WITH TIME ZONE,
    motivo_cambio VARCHAR(250) NOT NULL DEFAULT 'Alta e Instalación Inicial',
    operador_id UUID REFERENCES admin.usuarios(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_hist_equipos_id ON admin.historial_equipos_clientes (id_equipo);
CREATE INDEX IF NOT EXISTS idx_hist_equipos_cliente ON admin.historial_equipos_clientes (id_cliente);

-- ----------------------------------------------------
-- 4. DISPARADOR (TRIGGER) DE RED: LEASES KEA DHCP
-- ----------------------------------------------------
CREATE OR REPLACE FUNCTION admin.fn_trigger_log_kea_lease()
RETURNS TRIGGER AS $$
DECLARE
    v_id_cliente INT;
    v_id_servicio INT;
    v_ip_inet INET;
BEGIN
    -- Convertir la dirección entera de Kea a formato INET nativo de Postgres
    v_ip_inet := ('0.0.0.0'::inet + NEW.address);

    -- Buscar cliente/servicio de forma ultra-rápida (gracias a los índices creados)
    SELECT id_cliente, id INTO v_id_cliente, v_id_servicio
    FROM admin.servicios_clientes
    WHERE ip_cm = v_ip_inet OR ip_cpe = v_ip_inet
    LIMIT 1;

    -- Manejo de INSERT (Nueva concesión asignada por Kea)
    IF (TG_OP = 'INSERT') THEN
        -- Marcar leases históricos previos como finalizados (NOW) si existieran huérfanos para esa IP
        UPDATE admin.historial_leases_ip
        SET fecha_hasta = NOW()
        WHERE ip = v_ip_inet AND fecha_hasta IS NULL;

        -- Registrar la nueva concesión
        INSERT INTO admin.historial_leases_ip (ip, mac, id_cliente, id_servicio, fecha_desde, fecha_hasta)
        VALUES (
            v_ip_inet,
            encode(NEW.hwaddr, 'hex')::macaddr,
            v_id_cliente,
            v_id_servicio,
            NOW(),
            NEW.expire
        );

    -- Manejo de UPDATE (Renovaciones o recambio físico de router del usuario)
    ELSIF (TG_OP = 'UPDATE') THEN
        IF (OLD.hwaddr <> NEW.hwaddr OR OLD.address <> NEW.address) THEN
            -- Cerrar el lease temporal anterior de esta IP
            UPDATE admin.historial_leases_ip
            SET fecha_hasta = NOW()
            WHERE ip = ('0.0.0.0'::inet + OLD.address) AND fecha_hasta IS NULL;

            -- Registrar el nuevo bloque del lease renovado
            INSERT INTO admin.historial_leases_ip (ip, mac, id_cliente, id_servicio, fecha_desde, fecha_hasta)
            VALUES (
                v_ip_inet,
                encode(NEW.hwaddr, 'hex')::macaddr,
                v_id_cliente,
                v_id_servicio,
                NOW(),
                NEW.expire
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Inyección del trigger reactivo en la base de datos de Kea
DROP TRIGGER IF EXISTS trg_log_kea_lease ON public.lease4;
CREATE TRIGGER trg_log_kea_lease
AFTER INSERT OR UPDATE ON public.lease4
FOR EACH ROW EXECUTE FUNCTION admin.fn_trigger_log_kea_lease();

-- ----------------------------------------------------
-- 5. DISPARADOR (TRIGGER) DE NEGOCIO: TRAZABILIDAD EQUIPAMIENTO
-- ----------------------------------------------------
CREATE OR REPLACE FUNCTION admin.fn_trigger_trazabilidad_equipamiento()
RETURNS TRIGGER AS $$
DECLARE
    v_operador_id UUID;
BEGIN
    -- Capturar el ID de operador actual de forma segura desde la sesión temporal inyectada desde C#
    BEGIN
        v_operador_id := NULLIF(current_setting('app.current_operator_id', true), '')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_operador_id := NULL;
    END;

    -- CASO 1: Alta de un nuevo servicio (Primera asignación de hardware)
    IF (TG_OP = 'INSERT' AND NEW.id_equipo IS NOT NULL) THEN
        INSERT INTO admin.historial_equipos_clientes 
            (id_equipo, id_cliente, id_servicio, fecha_entrega, motivo_cambio, operador_id)
        VALUES 
            (NEW.id_equipo, NEW.id_cliente, NEW.id, NOW(), 'Alta e Instalación Inicial', v_operador_id);

    -- CASO 2: Recambio de Hardware (Soporte Técnico / Upgrades)
    ELSIF (TG_OP = 'UPDATE') THEN
        IF (COALESCE(OLD.id_equipo, 0) <> COALESCE(NEW.id_equipo, 0)) THEN
            -- 1. Cerrar la custodia del equipo anterior
            IF (OLD.id_equipo IS NOT NULL) THEN
                UPDATE admin.historial_equipos_clientes
                SET fecha_devolucion = NOW(), motivo_cambio = 'Recambio / Retiro por Soporte Técnico'
                WHERE id_equipo = OLD.id_equipo AND id_cliente = OLD.id_cliente AND fecha_devolucion IS NULL;
            END IF;

            -- 2. Abrir la custodia del nuevo equipo asignado
            IF (NEW.id_equipo IS NOT NULL) THEN
                INSERT INTO admin.historial_equipos_clientes 
                    (id_equipo, id_cliente, id_servicio, fecha_entrega, motivo_cambio, operador_id)
                VALUES 
                    (NEW.id_equipo, NEW.id_cliente, NEW.id, NOW(), 'Soporte Técnico - Recambio de Módem', v_operador_id);
            END IF;
        END IF;

    -- CASO 3: Baja del servicio (Retiro definitivo del hardware para stock)
    ELSIF (TG_OP = 'DELETE' AND OLD.id_equipo IS NOT NULL) THEN
        UPDATE admin.historial_equipos_clientes
        SET fecha_devolucion = NOW(), motivo_cambio = 'Baja de Abonado / Retiro de Hardware', operador_id = v_operador_id
        WHERE id_equipo = OLD.id_equipo AND id_cliente = OLD.id_cliente AND fecha_devolucion IS NULL;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Inyección del trigger de inventario
DROP TRIGGER IF EXISTS trg_trazabilidad_equipamiento ON admin.servicios_clientes;
CREATE TRIGGER trg_trazabilidad_equipamiento
AFTER INSERT OR UPDATE OR DELETE ON admin.servicios_clientes
FOR EACH ROW EXECUTE FUNCTION admin.fn_trigger_trazabilidad_equipamiento();
