-- =========================================================================
-- ESQUEMA DE ADMINISTRACION DE USUARIOS Y RED (SPI SIMPLIFICADO)
-- =========================================================================

CREATE SCHEMA admin;

-- Asegurar tipos de identificadores oficiales y custom en el esquema de Kea
INSERT INTO public.host_identifier_type (type, name) VALUES 
(0, 'hw-address'),
(1, 'duid'),
(2, 'circuit-id'),
(3, 'client-id'),
(4, 'flex-id'),
(5, 'remote-id')
ON CONFLICT (type) DO NOTHING;

-- 1. TABLA DE CMTSs (Nodos Principales)
CREATE TABLE admin.cmts (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    ip_relay INET NOT NULL, -- IP de Relay (giaddr) utilizada por este CMTS
    descripcion VARCHAR(200),
    snmp_comunidad_read VARCHAR(100) DEFAULT 'public',
    snmp_comunidad_write VARCHAR(100) DEFAULT 'private',
    snmp_port INT DEFAULT 161
);

-- 2. TABLA DE MARCAS DE EQUIPOS
CREATE TABLE admin.marcas (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE
);

-- 3. TABLA DE MODELOS DE EQUIPOS (DOCSIS y GPON)
CREATE TABLE admin.modelos (
    id SERIAL PRIMARY KEY,
    id_marca INT NOT NULL REFERENCES admin.marcas(id) ON DELETE RESTRICT,
    nombre VARCHAR(100) NOT NULL,
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN ('DOCSIS', 'GPON')), -- Clasificación tecnológica
    descripcion VARCHAR(200),
    UNIQUE (id_marca, nombre)
);

-- 4. TABLA DE EQUIPOS FISICOS (Cablemodems o ONUs en stock/servicio)
CREATE TABLE admin.equipos (
    id SERIAL PRIMARY KEY,
    id_modelo INT NOT NULL REFERENCES admin.modelos(id) ON DELETE RESTRICT,
    mac MACADDR NOT NULL UNIQUE, -- Valida automáticamente el formato MAC (ej: 7c:b2:1b:a0:00:f6)
    numero_serie VARCHAR(100) UNIQUE,
    estado VARCHAR(50) DEFAULT 'INVENTARIO' CHECK (estado IN ('INVENTARIO', 'ACTIVO', 'SUSPENDIDO', 'BAJA', 'FALLADO')),
    fecha_alta TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 5. TABLA DE PAISES
CREATE TABLE admin.paises (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE
);

-- 5.1 TABLA DE PROVINCIAS
CREATE TABLE admin.provincias (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    id_pais INT NOT NULL REFERENCES admin.paises(id) ON DELETE RESTRICT,
    CONSTRAINT uq_provincia_pais UNIQUE (nombre, id_pais)
);

-- 5.2 TABLA DE LOCALIDADES
CREATE TABLE admin.localidades (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    id_provincia INT NOT NULL REFERENCES admin.provincias(id) ON DELETE RESTRICT,
    CONSTRAINT uq_localidad_provincia UNIQUE (nombre, id_provincia)
);

-- 5.3 TABLA DE CLIENTES (Comercial)
CREATE TABLE admin.clientes (
    id SERIAL PRIMARY KEY,
    razon_social VARCHAR(200) NOT NULL,
    cuit_dni VARCHAR(20) NOT NULL UNIQUE,
    telefono VARCHAR(50),
    email VARCHAR(100),
    calle VARCHAR(150),
    altura VARCHAR(50),
    id_localidad INT REFERENCES admin.localidades(id) ON DELETE SET NULL,
    codigo VARCHAR(50) UNIQUE,
    latitud NUMERIC(10, 8),
    longitud NUMERIC(11, 8),
    direccion VARCHAR(200),
    fecha_alta TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. TABLA DE PAQUETES (Planes de internet con bootfile y clase DHCP)
CREATE TABLE admin.paquetes (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    velocidad_bajada_kbps INT NOT NULL,
    velocidad_subida_kbps INT NOT NULL,
    bootfile VARCHAR(150), -- Archivo de configuración descargado por TFTP (DOCSIS)
    dhcp4_client_class VARCHAR(100), -- Nombre de la clase DHCP en Kea (Ej: 'cpe-100M-10M')
    estado BOOLEAN DEFAULT TRUE
);

-- 7. TABLA DE SUBREDES (Mapeadas a cada CMTS y clasificadas por tipo de red)
CREATE TABLE admin.subredes (
    id SERIAL PRIMARY KEY,
    id_cmts INT NOT NULL REFERENCES admin.cmts(id) ON DELETE RESTRICT,
    nombre VARCHAR(100) NOT NULL,
    cidr CIDR NOT NULL, -- Dirección CIDR de la red (Ej: '172.18.110.0/23')
    gateway INET NOT NULL, -- Puerta de enlace (Ej: '172.18.110.1')
    tipo VARCHAR(50) NOT NULL CHECK (tipo IN ('CM', 'CPE')), -- CM (Gestión) o CPE (Navegación)
    descripcion VARCHAR(200)
);

-- 8. TABLA DE POOLS DHCP (Rangos de asignación asociados al plan comercial)
CREATE TABLE admin.pools (
    id SERIAL PRIMARY KEY,
    id_subred INT NOT NULL REFERENCES admin.subredes(id) ON DELETE CASCADE,
    rango_inicio INET NOT NULL,
    rango_fin INET NOT NULL,
    id_paquete INT REFERENCES admin.paquetes(id) ON DELETE SET NULL, -- Asignado a un plan de velocidad (Retrocompatibilidad)
    client_class VARCHAR(100) NULL, -- Clase DHCP Kea (Ej: 'cpe-dhcp-privadas')
    es_estatico BOOLEAN DEFAULT FALSE, -- Si es TRUE, el pool se usa solo para IPAM/sugerencias de IPs estáticas y no se envía a Kea DHCP
    CONSTRAINT check_rango CHECK (rango_inicio <= rango_fin)
);

-- 9. TABLA DE SERVICIOS ACTIVOS (Suscripción/Vínculo Comercial y Técnico)
CREATE TABLE admin.servicios_clientes (
    id SERIAL PRIMARY KEY,
    id_cliente INT NOT NULL REFERENCES admin.clientes(id) ON DELETE RESTRICT,
    id_equipo INT NOT NULL UNIQUE REFERENCES admin.equipos(id) ON DELETE RESTRICT,
    id_paquete INT NOT NULL REFERENCES admin.paquetes(id) ON DELETE RESTRICT,
    id_cmts INT NOT NULL REFERENCES admin.cmts(id) ON DELETE RESTRICT,
    ip_cm INET,    -- IP fija opcional del Cablemodem. Si es NULL, toma IP dinámica de gestión.
    ip_cpe INET,   -- IP fija opcional del Router. Si es NULL, toma IP dinámica del pool de su plan.
    estado VARCHAR(50) DEFAULT 'ACTIVO' CHECK (estado IN ('ACTIVO', 'SUSPENDIDO', 'BAJA')),
    fecha_alta TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- TRIGGER DE SINCRONIZACION AUTOMATICA EN TIEMPO REAL CON KEA DHCP
-- =========================================================================

CREATE OR REPLACE FUNCTION admin.sync_servicio_to_kea_hosts()
RETURNS TRIGGER AS $$
DECLARE
    v_old_mac MACADDR;
    v_new_mac MACADDR;
    v_old_mac_bytes BYTEA;
    v_new_mac_bytes BYTEA;
    v_ip_cm_int BIGINT;
    v_ip_cpe_int BIGINT;
    v_bootfile VARCHAR(150);
    v_pack_class VARCHAR(100);
    v_flex_id_str VARCHAR(100);
    v_host_id_cm INT;
    v_subnet_id_cm INT;
    v_subnet_id_cpe INT;
BEGIN
    -- 1. Identificar escenarios de cambio de equipo (Evitar registros huérfanos)
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        SELECT mac INTO v_old_mac FROM admin.equipos WHERE id = OLD.id_equipo;
        IF v_old_mac IS NOT NULL THEN
            v_old_mac_bytes := DECODE(replace(replace(v_old_mac::text, ':', ''), '.', ''), 'hex');
        END IF;
    END IF;

    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        SELECT mac INTO v_new_mac FROM admin.equipos WHERE id = NEW.id_equipo;
        IF v_new_mac IS NOT NULL THEN
            v_new_mac_bytes := DECODE(replace(replace(v_new_mac::text, ':', ''), '.', ''), 'hex');
        END IF;
    END IF;

    -- 2. Limpieza Absoluta en Kea (Usamos la MAC vieja si existía, o buscamos por ID de servicio en JSONB)
    IF v_old_mac_bytes IS NOT NULL THEN
        DELETE FROM public.hosts WHERE dhcp_identifier = v_old_mac_bytes;
        -- Liberación real e instantánea de Leases DHCP en Kea (Tanto para el Cablemodem como para sus CPEs asociados)
        DELETE FROM public.lease4 WHERE hwaddr = v_old_mac_bytes OR remote_id = v_old_mac_bytes;
    END IF;

    IF v_new_mac_bytes IS NOT NULL THEN
        -- Limpieza preventiva de leases previos para el nuevo módem y CPEs asociados para iniciar sin caché
        DELETE FROM public.lease4 WHERE hwaddr = v_new_mac_bytes OR remote_id = v_new_mac_bytes;
    END IF;
    
    -- Limpieza de seguridad rápida y segura por texto en user_context para evitar excepciones de casteo JSON
    DELETE FROM public.hosts 
    WHERE user_context LIKE '%"servicio_id": ' || COALESCE(OLD.id, NEW.id) || '%';

    -- 3. Manejo de Bajas o Suspensiones
    IF (TG_OP = 'DELETE') OR (NEW.estado <> 'ACTIVO') THEN
        -- Liberar o suspender el equipo viejo/actual
        UPDATE admin.equipos 
        SET estado = CASE WHEN TG_OP = 'DELETE' THEN 'INVENTARIO' ELSE 'SUSPENDIDO' END
        WHERE id = COALESCE(OLD.id_equipo, NEW.id_equipo);
        
        -- Si cambió el equipo en un UPDATE y pasa a inactivo, mandamos el viejo a inventario
        IF TG_OP = 'UPDATE' AND OLD.id_equipo <> NEW.id_equipo THEN
            UPDATE admin.equipos SET estado = 'INVENTARIO' WHERE id = OLD.id_equipo;
        END IF;

        RETURN COALESCE(NEW, OLD);
    END IF;

    -- Si es un UPDATE y cambiaron el módem, el viejo vuelve a inventario
    IF TG_OP = 'UPDATE' AND OLD.id_equipo <> NEW.id_equipo THEN
        UPDATE admin.equipos SET estado = 'INVENTARIO' WHERE id = OLD.id_equipo;
    END IF;

    -- Si no hay equipo asignado ni MAC, no podemos aprovisionar en Kea
    IF v_new_mac_bytes IS NULL THEN
        RETURN NEW;
    END IF;

    -- 4. Obtener datos del plan contratado
    SELECT bootfile, dhcp4_client_class INTO v_bootfile, v_pack_class 
    FROM admin.paquetes 
    WHERE id = NEW.id_paquete;

    -- Obtener los IDs de subred correspondientes al CMTS del cliente para CM y CPE
    SELECT id INTO v_subnet_id_cm 
    FROM admin.subredes 
    WHERE id_cmts = NEW.id_cmts AND tipo = 'CM' 
    LIMIT 1;

    -- Seleccionar la subred de CPE adecuada. Si tiene IP fija, buscamos la subred que contenga dicha IP.
    IF NEW.ip_cpe IS NOT NULL THEN
        SELECT id INTO v_subnet_id_cpe 
        FROM admin.subredes 
        WHERE id_cmts = NEW.id_cmts AND tipo = 'CPE' AND NEW.ip_cpe <<= cidr
        LIMIT 1;
    END IF;

    -- Si no tiene IP fija, buscamos la subred de CPE que tenga un pool dinámico asociado a la clase de este plan
    IF v_subnet_id_cpe IS NULL THEN
        SELECT s.id INTO v_subnet_id_cpe
        FROM admin.subredes s
        JOIN admin.pools p ON p.id_subred = s.id
        WHERE s.id_cmts = NEW.id_cmts 
          AND s.tipo = 'CPE' 
          AND p.client_class = v_pack_class
          AND COALESCE(p.es_estatico, FALSE) = FALSE
        LIMIT 1;
    END IF;

    -- Fallback de seguridad (tomar la primera CPE por defecto)
    IF v_subnet_id_cpe IS NULL THEN
        SELECT id INTO v_subnet_id_cpe 
        FROM admin.subredes 
        WHERE id_cmts = NEW.id_cmts AND tipo = 'CPE' 
        LIMIT 1;
    END IF;

    -- 5. Registrar Cablemodem (Tipo 0)
    v_ip_cm_int := CASE WHEN NEW.ip_cm IS NOT NULL THEN (NEW.ip_cm - '0.0.0.0'::inet) ELSE NULL END;
    
    INSERT INTO public.hosts (dhcp_identifier, dhcp_identifier_type, dhcp4_subnet_id, ipv4_address, dhcp4_client_classes, dhcp4_boot_file_name, dhcp4_next_server, user_context)
    VALUES (
        v_new_mac_bytes, 
        0, 
        v_subnet_id_cm,
        v_ip_cm_int,
        'docsis_modems',
        v_bootfile,
        ('192.168.2.106'::inet - '0.0.0.0'::inet),
        jsonb_build_object(
            'tipo', 'Cablemodem',
            'servicio_id', NEW.id,
            'cliente_id', NEW.id_cliente,
            'cmts_id', NEW.id_cmts
        )
    ) RETURNING host_id INTO v_host_id_cm;

    -- 5.1 Inyectar el BOOTFILE (Opción 67)
    IF v_bootfile IS NOT NULL AND v_bootfile <> '' THEN
        INSERT INTO public.dhcp4_options (code, value, formatted_value, space, scope_id, host_id, persistent)
        VALUES (
            67, 
            v_bootfile::bytea, 
            v_bootfile, 
            'dhcp4',
            3, 
            v_host_id_cm,
            true
        );
    END IF;

    -- 6. Registrar CPE del Cliente (Tipo 4 - flex-id para Option 82 Remote-ID)
    v_ip_cpe_int := CASE WHEN NEW.ip_cpe IS NOT NULL THEN (NEW.ip_cpe - '0.0.0.0'::inet) ELSE NULL END;
    
    INSERT INTO public.hosts (dhcp_identifier, dhcp_identifier_type, dhcp4_subnet_id, ipv4_address, dhcp4_client_classes, user_context)
    VALUES (
        v_new_mac_bytes, 
        4, -- flex-id (Option 82 Remote-ID)
        v_subnet_id_cpe,
        v_ip_cpe_int,
        v_pack_class, 
        jsonb_build_object(
            'tipo', 'CPE',
            'servicio_id', NEW.id,
            'cliente_id', NEW.id_cliente,
            'cmts_id', NEW.id_cmts
        )
    );

    -- 7. Actualizar el estado del nuevo equipo a ACTIVO
    UPDATE admin.equipos SET estado = 'ACTIVO' WHERE id = NEW.id_equipo;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear el Trigger asociado a la tabla servicios_clientes
CREATE TRIGGER trg_sync_servicio_to_kea_hosts
AFTER INSERT OR UPDATE OR DELETE ON admin.servicios_clientes
FOR EACH ROW EXECUTE FUNCTION admin.sync_servicio_to_kea_hosts();

-- =========================================================================
-- LOGICA DE PREVENCION CONTRA TRASLAPES DE POOLS EN LA MISMA SUBRED
-- =========================================================================

CREATE OR REPLACE FUNCTION admin.fn_check_pool_overlap()
RETURNS TRIGGER AS $$
BEGIN
    -- Validar si existe algún pool en la misma subred que se traslape
    IF EXISTS (
        SELECT 1 FROM admin.pools
        WHERE id_subred = NEW.id_subred
          AND id <> COALESCE(NEW.id, -1) -- Omitir el mismo registro en UPDATE
          AND NOT (NEW.rango_fin < rango_inicio OR NEW.rango_inicio > rango_fin)
    ) THEN
        RAISE EXCEPTION 'El rango de IPs ingresado (% - %) se traslapa con un pool existente en la misma subred.', 
            NEW.rango_inicio, NEW.rango_fin;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_pool_overlap ON admin.pools;
CREATE TRIGGER trg_check_pool_overlap
BEFORE INSERT OR UPDATE ON admin.pools
FOR EACH ROW EXECUTE FUNCTION admin.fn_check_pool_overlap();
