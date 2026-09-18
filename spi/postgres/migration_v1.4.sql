-- =========================================================================
-- SPI V1.4 - MIGRACIÓN DE ENDURECIMIENTO Y ESTANDARIZACIÓN DE BASE DE DATOS
-- =========================================================================
-- Ejecutar este script sobre la base de datos 'dhcp' para aplicar los cambios en caliente.
-- Comando sugerido:
-- docker exec -i isp-postgres psql -U postgres -d dhcp < migration_v1.4.sql
-- =========================================================================

BEGIN;

-- 1. MODIFICACIÓN DE RESTRICCIONES GEOGRÁFICAS (DE CASCADE A RESTRICT)
-- Frena borrados accidentales de provincias/países si tienen localidades o clientes activos
ALTER TABLE admin.provincias DROP CONSTRAINT IF EXISTS provincias_id_pais_fkey;
ALTER TABLE admin.provincias ADD CONSTRAINT provincias_id_pais_fkey 
    FOREIGN KEY (id_pais) REFERENCES admin.paises(id) ON DELETE RESTRICT;

ALTER TABLE admin.localidades DROP CONSTRAINT IF EXISTS localidades_id_provincia_fkey;
ALTER TABLE admin.localidades ADD CONSTRAINT localidades_id_provincia_fkey 
    FOREIGN KEY (id_provincia) REFERENCES admin.provincias(id) ON DELETE RESTRICT;

-- 2. MODIFICACIÓN DE RESTRICCIÓN EN SERVICIOS (DE CASCADE A RESTRICT)
-- Protege las suscripciones activas ante borrados de clientes
ALTER TABLE admin.servicios_clientes DROP CONSTRAINT IF EXISTS servicios_clientes_id_cliente_fkey;
ALTER TABLE admin.servicios_clientes ADD CONSTRAINT servicios_clientes_id_cliente_fkey 
    FOREIGN KEY (id_cliente) REFERENCES admin.clientes(id) ON DELETE RESTRICT;

-- 3. ESTANDARIZACIÓN SNMP PARA CMTSs (CAMPOS POR DEFECTO PARA TELEMETRÍA)
ALTER TABLE admin.cmts ADD COLUMN IF NOT EXISTS snmp_comunidad_read VARCHAR(100) DEFAULT 'public';
ALTER TABLE admin.cmts ADD COLUMN IF NOT EXISTS snmp_comunidad_write VARCHAR(100) DEFAULT 'private';
ALTER TABLE admin.cmts ADD COLUMN IF NOT EXISTS snmp_port INT DEFAULT 161;

-- 4. HARDENING DE SEGURIDAD PARA ROLES DE USUARIO
-- Asegura que ningún operador o script SQL inyecte un rol no autorizado
ALTER TABLE admin.usuarios DROP CONSTRAINT IF EXISTS chk_usuario_rol;
ALTER TABLE admin.usuarios ADD CONSTRAINT chk_usuario_rol CHECK (rol IN ('ADMIN', 'OPERADOR', 'TECNICO'));

-- 5. IMPLEMENTACIÓN DE PREVENCIÓN CONTRA TRASLAPES EN POOLS (IPAM SEGURO)
-- Función PL/pgSQL atómica e independiente de extensiones GiST
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

-- Inyectar el trigger en la tabla admin.pools
DROP TRIGGER IF EXISTS trg_check_pool_overlap ON admin.pools;
CREATE TRIGGER trg_check_pool_overlap
BEFORE INSERT OR UPDATE ON admin.pools
FOR EACH ROW EXECUTE FUNCTION admin.fn_check_pool_overlap();

COMMIT;
