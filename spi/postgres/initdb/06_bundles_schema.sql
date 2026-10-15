-- =========================================================================
-- ESQUEMA DE BUNDLES (giaddr) Y DISCRIMINACION DE RED EN KEA DHCP
-- =========================================================================

-- 1. TABLA DE BUNDLES (Múltiples interfaces/relays por CMTS)
CREATE TABLE IF NOT EXISTS admin.bundles (
    id SERIAL PRIMARY KEY,
    id_cmts INT NOT NULL REFERENCES admin.cmts(id) ON DELETE CASCADE,
    nombre VARCHAR(100) NOT NULL, -- ej: 'ipbundle1'
    ip_giaddr INET NOT NULL UNIQUE, -- ej: '10.200.60.1' (Relay Agent IP / Gateway Primario del Bundle)
    descripcion VARCHAR(200),
    CONSTRAINT uq_bundle_cmts_nombre UNIQUE (id_cmts, nombre)
);

-- 2. ASOCIACION DE SUBREDES Y SERVICIOS CON BUNDLES
ALTER TABLE admin.subredes 
ADD COLUMN IF NOT EXISTS id_bundle INT REFERENCES admin.bundles(id) ON DELETE RESTRICT;

ALTER TABLE admin.servicios_clientes 
ADD COLUMN IF NOT EXISTS id_bundle INT REFERENCES admin.bundles(id) ON DELETE RESTRICT;

-- 3. MIGRACION DE DATOS EXISTENTES (Creación de Bundles por defecto)
DO $$
DECLARE
    r_cmts RECORD;
    v_bundle_id INT;
    v_giaddr INET;
BEGIN
    FOR r_cmts IN SELECT id, nombre, ip_relay FROM admin.cmts LOOP
        -- Obtener gateway de subred CM o usar ip_relay
        SELECT gateway INTO v_giaddr 
        FROM admin.subredes 
        WHERE id_cmts = r_cmts.id AND tipo = 'CM' 
        LIMIT 1;
        
        IF v_giaddr IS NULL THEN
            v_giaddr := r_cmts.ip_relay;
        END IF;

        -- Insertar bundle por defecto
        INSERT INTO admin.bundles (id_cmts, nombre, ip_giaddr, descripcion)
        VALUES (r_cmts.id, 'ipbundle-default-' || r_cmts.id, v_giaddr, 'Bundle por defecto migrado automáticamente')
        ON CONFLICT (ip_giaddr) DO NOTHING;

        -- Obtener ID del bundle
        SELECT id INTO v_bundle_id FROM admin.bundles WHERE ip_giaddr = v_giaddr;

        -- Enlazar subredes huérfanas de este CMTS
        IF v_bundle_id IS NOT NULL THEN
            UPDATE admin.subredes 
            SET id_bundle = v_bundle_id 
            WHERE id_cmts = r_cmts.id AND id_bundle IS NULL;

            UPDATE admin.servicios_clientes
            SET id_bundle = v_bundle_id
            WHERE id_cmts = r_cmts.id AND id_bundle IS NULL;
        END IF;
    END LOOP;
END $$;

-- 4. ACTUALIZACION DE LA FUNCION TRIGGER SINCRO KEA
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
    v_host_id_cm INT;
    v_subnet_id_cm INT;
    v_subnet_id_cpe INT;
    v_server_ip_str VARCHAR(100);
    v_server_ip_inet INET;
BEGIN
    -- 0. Obtener la IP de infraestructura de forma dinámica desde la tabla de configuraciones
    SELECT valor INTO v_server_ip_str 
    FROM admin.configuraciones 
    WHERE clave = 'infra_server_ip' 
    LIMIT 1;
    
    v_server_ip_inet := COALESCE(v_server_ip_str, '192.168.2.20')::inet;
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

    -- 2. Limpieza Absoluta en Kea (Usamos la MAC vieja y nueva si existían)
    IF v_old_mac_bytes IS NOT NULL THEN
        DELETE FROM public.hosts WHERE dhcp_identifier = v_old_mac_bytes;
        DELETE FROM public.lease4 WHERE hwaddr = v_old_mac_bytes OR remote_id = v_old_mac_bytes;
    END IF;

    IF v_new_mac_bytes IS NOT NULL THEN
        DELETE FROM public.hosts WHERE dhcp_identifier = v_new_mac_bytes;
        DELETE FROM public.lease4 WHERE hwaddr = v_new_mac_bytes OR remote_id = v_new_mac_bytes;
    END IF;
    
    IF OLD.id IS NOT NULL THEN
        DELETE FROM public.hosts WHERE user_context IS NOT NULL AND user_context <> '' AND (user_context::jsonb->>'servicio_id')::int = OLD.id;
    END IF;
    IF NEW.id IS NOT NULL THEN
        DELETE FROM public.hosts WHERE user_context IS NOT NULL AND user_context <> '' AND (user_context::jsonb->>'servicio_id')::int = NEW.id;
    END IF;

    -- 3. Manejo de Bajas o Suspensiones
    IF (TG_OP = 'DELETE') OR (NEW.estado <> 'ACTIVO') THEN
        UPDATE admin.equipos 
        SET estado = CASE WHEN TG_OP = 'DELETE' THEN 'INVENTARIO' ELSE 'SUSPENDIDO' END
        WHERE id = COALESCE(OLD.id_equipo, NEW.id_equipo);
        
        IF TG_OP = 'UPDATE' AND OLD.id_equipo <> NEW.id_equipo THEN
            UPDATE admin.equipos SET estado = 'INVENTARIO' WHERE id = OLD.id_equipo;
        END IF;

        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.id_equipo <> NEW.id_equipo THEN
        UPDATE admin.equipos SET estado = 'INVENTARIO' WHERE id = OLD.id_equipo;
    END IF;

    IF v_new_mac_bytes IS NULL THEN
        RETURN NEW;
    END IF;

    -- 4. Obtener datos del plan contratado
    SELECT bootfile, dhcp4_client_class INTO v_bootfile, v_pack_class 
    FROM admin.paquetes 
    WHERE id = NEW.id_paquete;

    -- Búsqueda de Subred CM (Cablemódem)
    IF NEW.id_bundle IS NOT NULL THEN
        SELECT id INTO v_subnet_id_cm FROM admin.subredes WHERE id_bundle = NEW.id_bundle AND tipo = 'CM' LIMIT 1;
    ELSIF NEW.id_cmts IS NOT NULL THEN
        SELECT id INTO v_subnet_id_cm FROM admin.subredes WHERE id_cmts = NEW.id_cmts AND tipo = 'CM' LIMIT 1;
    END IF;

    -- Búsqueda de Subred CPE: Vinculación por Bundle/CMTS y Clase DHCP del Paquete (v_pack_class)
    IF NEW.id_bundle IS NOT NULL AND v_pack_class IS NOT NULL AND v_pack_class <> '' THEN
        SELECT s.id INTO v_subnet_id_cpe
        FROM admin.subredes s
        JOIN admin.pools p ON p.id_subred = s.id
        WHERE s.id_bundle = NEW.id_bundle AND s.tipo = 'CPE' AND p.client_class = v_pack_class
        LIMIT 1;
    ELSIF NEW.id_cmts IS NOT NULL AND v_pack_class IS NOT NULL AND v_pack_class <> '' THEN
        SELECT s.id INTO v_subnet_id_cpe
        FROM admin.subredes s
        JOIN admin.pools p ON p.id_subred = s.id
        WHERE s.id_cmts = NEW.id_cmts AND s.tipo = 'CPE' AND p.client_class = v_pack_class
        LIMIT 1;
    END IF;

    -- Si el servicio asigna una IP CPE estática explícita, buscar por CIDR
    IF v_subnet_id_cpe IS NULL AND NEW.ip_cpe IS NOT NULL THEN
        SELECT id INTO v_subnet_id_cpe 
        FROM admin.subredes 
        WHERE tipo = 'CPE' AND NEW.ip_cpe <<= cidr
        LIMIT 1;
    END IF;

    -- 5. Registrar Cablemodem (Tipo 0 - hw-address)
    v_ip_cm_int := CASE WHEN NEW.ip_cm IS NOT NULL THEN (NEW.ip_cm - '0.0.0.0'::inet) ELSE NULL END;
    
    INSERT INTO public.hosts (dhcp_identifier, dhcp_identifier_type, dhcp4_subnet_id, ipv4_address, dhcp4_client_classes, dhcp4_boot_file_name, dhcp4_next_server, user_context)
    VALUES (
        v_new_mac_bytes, 
        0, 
        COALESCE(v_subnet_id_cm, 0),
        v_ip_cm_int,
        'docsis_modems',
        v_bootfile,
        (v_server_ip_inet - '0.0.0.0'::inet),
        jsonb_build_object(
            'tipo', 'Cablemodem',
            'servicio_id', NEW.id,
            'cliente_id', NEW.id_cliente,
            'cmts_id', NEW.id_cmts,
            'bundle_id', NEW.id_bundle
        )
    ) RETURNING host_id INTO v_host_id_cm;

    -- Inyectar BOOTFILE (Opción 67)
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
            COALESCE(v_subnet_id_cpe, 0),
            v_ip_cpe_int,
            v_pack_class, 
            jsonb_build_object(
                'tipo', 'CPE',
                'servicio_id', NEW.id,
                'cliente_id', NEW.id_cliente,
                'cmts_id', NEW.id_cmts,
                'bundle_id', NEW.id_bundle
            )
        );
    END IF;

    -- 7. Actualizar el estado del equipo
    UPDATE admin.equipos SET estado = 'ACTIVO' WHERE id = NEW.id_equipo;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
