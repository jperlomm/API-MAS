-- SPI Customer Change Audit Log & Automatically Rotated History
-- Author: Antigravity AI & ISP Network Architecture Team

-- ----------------------------------------------------
-- 1. TABLA UNIFICADA DE LOGS DE CLIENTES
-- ----------------------------------------------------
CREATE TABLE IF NOT EXISTS admin.auditoria_clientes (
    id BIGSERIAL PRIMARY KEY,
    id_cliente INT REFERENCES admin.clientes(id) ON DELETE SET NULL,
    nombre_cliente VARCHAR(200), -- Respaldo de seguridad por si el cliente es eliminado físicamente
    fecha TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    usuario VARCHAR(100) NOT NULL DEFAULT 'sistema_api',
    accion VARCHAR(100) NOT NULL, -- 'ALTA_CLIENTE', 'MODIFICACION_CLIENTE', 'BAJA_CLIENTE', 'ALTA_SERVICIO', 'MODIFICACION_SERVICIO', 'CAMBIO_EQUIPO', 'CAMBIO_ESTADO_SERVICIO', 'BAJA_SERVICIO'
    detalle TEXT NOT NULL,
    valores_anteriores JSONB,
    valores_nuevos JSONB
);

-- Índices de control para búsquedas ultra-rápidas por Cliente y Rango de Fecha
CREATE INDEX IF NOT EXISTS idx_auditoria_id_cliente ON admin.auditoria_clientes (id_cliente);
CREATE INDEX IF NOT EXISTS idx_auditoria_fecha ON admin.auditoria_clientes (fecha);

-- ----------------------------------------------------
-- 2. ROTACIÓN Y PURGADO AUTOMÁTICO (RETENCIÓN DE 180 DÍAS)
-- ----------------------------------------------------
CREATE OR REPLACE FUNCTION admin.fn_prune_auditoria_clientes()
RETURNS TRIGGER AS $$
BEGIN
    -- Eliminar automáticamente registros que exceden los 180 días de antigüedad
    DELETE FROM admin.auditoria_clientes
    WHERE fecha < NOW() - INTERVAL '180 days';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_prune_auditoria_clientes ON admin.auditoria_clientes;
CREATE TRIGGER trg_prune_auditoria_clientes
AFTER INSERT ON admin.auditoria_clientes
FOR EACH STATEMENT
EXECUTE FUNCTION admin.fn_prune_auditoria_clientes();

-- ----------------------------------------------------
-- 3. DISPARADOR (TRIGGER) PARA CAMBIOS EN CLIENTES (DATOS PERSONALES)
-- ----------------------------------------------------
CREATE OR REPLACE FUNCTION admin.fn_trigger_audit_clientes()
RETURNS TRIGGER AS $$
DECLARE
    v_operador_id UUID;
    v_username VARCHAR(100) := 'sistema_api';
    v_detalle TEXT;
BEGIN
    -- Capturar el ID del operador de la sesión inyectada por el Backend C#
    BEGIN
        v_operador_id := NULLIF(current_setting('app.current_operator_id', true), '')::uuid;
        IF v_operador_id IS NOT NULL THEN
            SELECT username INTO v_username FROM admin.usuarios WHERE id = v_operador_id;
            IF v_username IS NULL THEN
                v_username := 'operador_desconocido';
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_username := 'sistema_api';
    END;

    IF (TG_OP = 'INSERT') THEN
        INSERT INTO admin.auditoria_clientes (id_cliente, nombre_cliente, usuario, accion, detalle, valores_nuevos)
        VALUES (
            NEW.id,
            NEW.razon_social,
            v_username,
            'ALTA_CLIENTE',
            'Se dio de alta el abonado ' || NEW.razon_social || ' (Código: ' || COALESCE(NEW.codigo, '-') || ', CUIT/DNI: ' || NEW.cuit_dni || ').',
            to_jsonb(NEW)
        );
    ELSIF (TG_OP = 'UPDATE') THEN
        v_detalle := '';
        
        IF COALESCE(OLD.razon_social, '') <> COALESCE(NEW.razon_social, '') THEN
            v_detalle := v_detalle || 'Nombre: ' || COALESCE(OLD.razon_social, '-') || ' ➔ ' || COALESCE(NEW.razon_social, '-') || '. ';
        END IF;
        IF COALESCE(OLD.telefono, '') <> COALESCE(NEW.telefono, '') THEN
            v_detalle := v_detalle || 'Teléfono: ' || COALESCE(OLD.telefono, 'Ninguno') || ' ➔ ' || COALESCE(NEW.telefono, 'Ninguno') || '. ';
        END IF;
        IF COALESCE(OLD.email, '') <> COALESCE(NEW.email, '') THEN
            v_detalle := v_detalle || 'Email: ' || COALESCE(OLD.email, 'Ninguno') || ' ➔ ' || COALESCE(NEW.email, 'Ninguno') || '. ';
        END IF;
        IF COALESCE(OLD.direccion, '') <> COALESCE(NEW.direccion, '') THEN
            v_detalle := v_detalle || 'Dirección: ' || COALESCE(OLD.direccion, 'Ninguna') || ' ➔ ' || COALESCE(NEW.direccion, 'Ninguna') || '. ';
        END IF;
        IF COALESCE(OLD.codigo, '') <> COALESCE(NEW.codigo, '') THEN
            v_detalle := v_detalle || 'Código de Abonado: ' || COALESCE(OLD.codigo, '-') || ' ➔ ' || COALESCE(NEW.codigo, '-') || '. ';
        END IF;

        IF v_detalle <> '' THEN
            INSERT INTO admin.auditoria_clientes (id_cliente, nombre_cliente, usuario, accion, detalle, valores_anteriores, valores_nuevos)
            VALUES (
                NEW.id,
                NEW.razon_social,
                v_username,
                'MODIFICACION_CLIENTE',
                'Modificación de datos personales de ' || NEW.razon_social || ': ' || trim(v_detalle),
                to_jsonb(OLD),
                to_jsonb(NEW)
            );
        END IF;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO admin.auditoria_clientes (id_cliente, nombre_cliente, usuario, accion, detalle, valores_anteriores)
        VALUES (
            OLD.id,
            OLD.razon_social,
            v_username,
            'BAJA_CLIENTE',
            'Se eliminó definitivamente el abonado ' || OLD.razon_social || ' (Código: ' || COALESCE(OLD.codigo, '-') || ').',
            to_jsonb(OLD)
        );
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_audit_clientes ON admin.clientes;
CREATE TRIGGER trg_audit_clientes
AFTER INSERT OR UPDATE OR DELETE ON admin.clientes
FOR EACH ROW EXECUTE FUNCTION admin.fn_trigger_audit_clientes();

-- ----------------------------------------------------
-- 4. DISPARADOR (TRIGGER) PARA CAMBIOS EN SERVICIOS (TECNOLOGÍA Y PLANES)
-- ----------------------------------------------------
CREATE OR REPLACE FUNCTION admin.fn_trigger_audit_servicios()
RETURNS TRIGGER AS $$
DECLARE
    v_operador_id UUID;
    v_username VARCHAR(100) := 'sistema_api';
    v_cliente_nombre VARCHAR(200);
    v_detalle TEXT := '';
    
    -- Variables para nombres descriptivos
    v_old_mac MACADDR;
    v_new_mac MACADDR;
    v_old_plan VARCHAR(100);
    v_new_plan VARCHAR(100);
    v_old_cmts VARCHAR(100);
    v_new_cmts VARCHAR(100);
BEGIN
    -- Capturar el ID del operador de la sesión inyectada por el Backend C#
    BEGIN
        v_operador_id := NULLIF(current_setting('app.current_operator_id', true), '')::uuid;
        IF v_operador_id IS NOT NULL THEN
            SELECT username INTO v_username FROM admin.usuarios WHERE id = v_operador_id;
            IF v_username IS NULL THEN
                v_username := 'operador_desconocido';
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_username := 'sistema_api';
    END;

    -- Obtener nombre del abonado
    IF (TG_OP = 'DELETE') THEN
        SELECT razon_social INTO v_cliente_nombre FROM admin.clientes WHERE id = OLD.id_cliente;
    ELSE
        SELECT razon_social INTO v_cliente_nombre FROM admin.clientes WHERE id = NEW.id_cliente;
    END IF;

    IF (TG_OP = 'INSERT') THEN
        SELECT mac INTO v_new_mac FROM admin.equipos WHERE id = NEW.id_equipo;
        SELECT nombre INTO v_new_plan FROM admin.paquetes WHERE id = NEW.id_paquete;
        SELECT nombre INTO v_new_cmts FROM admin.cmts WHERE id = NEW.id_cmts;

        v_detalle := 'Se dio de alta el servicio de internet. ' ||
                     'Plan: ' || COALESCE(v_new_plan, 'ID ' || NEW.id_paquete) || '. ' ||
                     'Equipo MAC: ' || COALESCE(v_new_mac::text, 'ID ' || NEW.id_equipo) || '. ' ||
                     'CMTS: ' || COALESCE(v_new_cmts, 'Autodetección Reactiva') || '. ' ||
                     'IP CM: ' || COALESCE(NEW.ip_cm::text, 'Dinámica') || ', ' ||
                     'IP CPE: ' || COALESCE(NEW.ip_cpe::text, 'Dinámica') || '.';

        INSERT INTO admin.auditoria_clientes (id_cliente, nombre_cliente, usuario, accion, detalle, valores_nuevos)
        VALUES (NEW.id_cliente, v_cliente_nombre, v_username, 'ALTA_SERVICIO', v_detalle, to_jsonb(NEW));

    ELSIF (TG_OP = 'UPDATE') THEN
        v_detalle := '';

        -- Detectar Cambio de Estado
        IF OLD.estado <> NEW.estado THEN
            v_detalle := v_detalle || 'Estado del servicio: ' || OLD.estado || ' ➔ ' || NEW.estado || '. ';
        END IF;

        -- Detectar Cambio de Plan
        IF OLD.id_paquete <> NEW.id_paquete THEN
            SELECT nombre INTO v_old_plan FROM admin.paquetes WHERE id = OLD.id_paquete;
            SELECT nombre INTO v_new_plan FROM admin.paquetes WHERE id = NEW.id_paquete;
            v_detalle := v_detalle || 'Cambio de plan: ' || COALESCE(v_old_plan, 'ID ' || OLD.id_paquete) || ' ➔ ' || COALESCE(v_new_plan, 'ID ' || NEW.id_paquete) || '. ';
        END IF;

        -- Detectar Cambio/Recambio de Equipo (Módem)
        IF OLD.id_equipo <> NEW.id_equipo THEN
            SELECT mac INTO v_old_mac FROM admin.equipos WHERE id = OLD.id_equipo;
            SELECT mac INTO v_new_mac FROM admin.equipos WHERE id = NEW.id_equipo;
            v_detalle := v_detalle || 'Recambio de módem: ' || COALESCE(v_old_mac::text, 'ID ' || OLD.id_equipo) || ' ➔ ' || COALESCE(v_new_mac::text, 'ID ' || NEW.id_equipo) || '. ';
        END IF;

        -- Detectar Cambios de Direccionamiento IP
        IF COALESCE(OLD.ip_cm::text, 'Dinamica') <> COALESCE(NEW.ip_cm::text, 'Dinamica') THEN
            v_detalle := v_detalle || 'IP de Gestión (CM): ' || COALESCE(OLD.ip_cm::text, 'Dinámica') || ' ➔ ' || COALESCE(NEW.ip_cm::text, 'Dinámica') || '. ';
        END IF;
        IF COALESCE(OLD.ip_cpe::text, 'Dinamica') <> COALESCE(NEW.ip_cpe::text, 'Dinamica') THEN
            v_detalle := v_detalle || 'IP de Cliente (CPE): ' || COALESCE(OLD.ip_cpe::text, 'Dinámica') || ' ➔ ' || COALESCE(NEW.ip_cpe::text, 'Dinámica') || '. ';
        END IF;

        -- Detectar Cambio de Nodo/CMTS (Usa IS DISTINCT FROM porque id_cmts es anulable)
        IF OLD.id_cmts IS DISTINCT FROM NEW.id_cmts THEN
            SELECT nombre INTO v_old_cmts FROM admin.cmts WHERE id = OLD.id_cmts;
            SELECT nombre INTO v_new_cmts FROM admin.cmts WHERE id = NEW.id_cmts;
            v_detalle := v_detalle || 'CMTS de conexión: ' || COALESCE(v_old_cmts, 'Autodetección') || ' ➔ ' || COALESCE(v_new_cmts, 'Autodetección') || '. ';
        END IF;

        IF v_detalle <> '' THEN
            INSERT INTO admin.auditoria_clientes (id_cliente, nombre_cliente, usuario, accion, detalle, valores_anteriores, valores_nuevos)
            VALUES (
                NEW.id_cliente,
                v_cliente_nombre,
                v_username,
                CASE WHEN OLD.estado <> NEW.estado THEN 'CAMBIO_ESTADO_SERVICIO'
                     WHEN OLD.id_equipo <> NEW.id_equipo THEN 'CAMBIO_EQUIPO'
                     ELSE 'MODIFICACION_SERVICIO' END,
                'Modificación del servicio de ' || v_cliente_nombre || ': ' || trim(v_detalle),
                to_jsonb(OLD),
                to_jsonb(NEW)
            );
        END IF;

    ELSIF (TG_OP = 'DELETE') THEN
        SELECT mac INTO v_old_mac FROM admin.equipos WHERE id = OLD.id_equipo;
        SELECT nombre INTO v_old_plan FROM admin.paquetes WHERE id = OLD.id_paquete;

        v_detalle := 'Se dio de BAJA el servicio de internet. ' ||
                     'Plan contratado: ' || COALESCE(v_old_plan, 'ID ' || OLD.id_paquete) || '. ' ||
                     'Módem (MAC): ' || COALESCE(v_old_mac::text, 'ID ' || OLD.id_equipo) || '.';

        INSERT INTO admin.auditoria_clientes (id_cliente, nombre_cliente, usuario, accion, detalle, valores_anteriores)
        VALUES (OLD.id_cliente, v_cliente_nombre, v_username, 'BAJA_SERVICIO', v_detalle, to_jsonb(OLD));
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_audit_servicios ON admin.servicios_clientes;
CREATE TRIGGER trg_audit_servicios
AFTER INSERT OR UPDATE OR DELETE ON admin.servicios_clientes
FOR EACH ROW EXECUTE FUNCTION admin.fn_trigger_audit_servicios();
