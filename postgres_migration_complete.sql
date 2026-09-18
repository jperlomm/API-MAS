-- =============================================================================
-- SCRIPT DE MIGRACIÓN COMPLETO (ETL AUTOMATIZADO VÍA POSTGRES_FDW)
-- =============================================================================
-- Este script realiza la migración completa:
-- 1. Configura FDW para conectar la base nueva 'dhcp' con la sandbox legacy 'spi_legacy'.
-- 2. Migra todos los catálogos estáticos (Fase 1: Países, Provincias, Localidades, Modelos, Paquetes, CMTSs).
-- 3. Crea la función para migrar clientes, equipos y servicios segmentados de forma aislada por CMTS (Fase 2).
-- =============================================================================

BEGIN;

-- =============================================================================
-- PARTE 1: CONFIGURACIÓN DE POSTGRES_FDW (Enlace con la DB Sandbox Legacy)
-- =============================================================================

-- Crear la extensión de Foreign Data Wrapper
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Crear el servidor externo apuntando al contenedor temporal legacy (puerto 5435 de la IP de infraestructura)
DROP SERVER IF EXISTS legacy_server CASCADE;
CREATE SERVER legacy_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host '192.168.2.106', port '5435', dbname 'spi_legacy');

-- Crear el mapeo de usuarios (Usa las credenciales 'postgres' / 'P0stgr3s_legacy_pwd' de tu sandbox)
DROP USER MAPPING IF EXISTS FOR postgres SERVER legacy_server;
CREATE USER MAPPING FOR postgres
    SERVER legacy_server
    OPTIONS (user 'postgres', password 'P0stgr3s_legacy_pwd');

-- Crear un esquema aislado para importar las tablas del legacy y no contaminar el esquema público
CREATE SCHEMA IF NOT EXISTS legacy_import;

-- Importar las tablas necesarias desde el sandbox legacy a nuestro esquema temporal de importación
IMPORT FOREIGN SCHEMA public 
FROM SERVER legacy_server 
INTO legacy_import;

-- =============================================================================
-- PARTE 2: MIGRACIÓN DE CATÁLOGOS ESTÁTICOS (Fase 1)
-- =============================================================================

-- 1. Países
INSERT INTO admin.paises (id, nombre)
SELECT DISTINCT id, nombre
FROM legacy_import.com_paises
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre;

-- 2. Provincias
INSERT INTO admin.provincias (id, id_pais, nombre)
SELECT DISTINCT id, id_pais, nombre
FROM legacy_import.com_provincias
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, id_pais = EXCLUDED.id_pais;

-- 3. Localidades
INSERT INTO admin.localidades (id, id_provincia, nombre)
SELECT DISTINCT id, id_provincia, nombre
FROM legacy_import.com_localidades
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, id_provincia = EXCLUDED.id_provincia;

-- 4. Marcas y Modelos de Cablemódems
INSERT INTO admin.marcas (id, nombre)
SELECT DISTINCT id, nombre
FROM legacy_import.tec_marcas
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre;

INSERT INTO admin.modelos (id, id_marca, nombre, tipo, descripcion)
SELECT DISTINCT 
    m.id, 
    m.id_marca, 
    m.descripcion AS nombre, 
    'DOCSIS' AS tipo, -- En el legacy todo el equipamiento de cablemódems es DOCSIS
    m.descripcion AS descripcion
FROM legacy_import.tec_modelos m
ON CONFLICT (id) DO UPDATE SET id_marca = EXCLUDED.id_marca, nombre = EXCLUDED.nombre, tipo = EXCLUDED.tipo, descripcion = EXCLUDED.descripcion;

-- 5. Paquetes Comerciales (Planes de Internet)
INSERT INTO admin.paquetes (id, nombre, velocidad_bajada_kbps, velocidad_subida_kbps, bootfile, dhcp4_client_class)
SELECT DISTINCT 
    cp.id, 
    cp.descripcion AS nombre, 
    COALESCE((regexp_match(cp.descripcion, '([0-9]+)\s*M\s*/'))[1]::int * 1024, 51200) AS velocidad_bajada_kbps, 
    COALESCE(replace((regexp_match(cp.descripcion, '/\s*([0-9]+(?:,[0-9]+)?)\s*M'))[1], ',', '.')::numeric * 1024, (regexp_match(cp.descripcion, '/\s*([0-9]+)'))[1]::numeric, 10240)::int AS velocidad_subida_kbps,
    -- Generamos bootfile y clase dhcp dinámicos en base a su ancho de banda
    CONCAT('boot_', COALESCE((regexp_match(cp.descripcion, '([0-9]+)\s*M\s*/'))[1]::int, 50), 'm.bin') AS bootfile,
    CONCAT('cpe-', COALESCE((regexp_match(cp.descripcion, '([0-9]+)\s*M\s*/'))[1]::int, 50), 'M-', COALESCE(replace((regexp_match(cp.descripcion, '/\s*([0-9]+(?:,[0-9]+)?)\s*M'))[1], ',', '.')::numeric::int, (regexp_match(cp.descripcion, '/\s*([0-9]+)'))[1]::numeric::int / 1024, 10), 'M') AS dhcp4_client_class
FROM legacy_import.com_packs cp
WHERE NOT EXISTS (
    SELECT 1 FROM admin.paquetes p WHERE p.nombre = cp.descripcion OR p.id = cp.id
);

-- 6. Autodescubrimiento y Alta de los 16 CMTSs Activos
-- Buscamos los dispositivos referenciados como CMTS de cablemódems en la propiedad técnica 1009
INSERT INTO admin.cmts (id, nombre, ip_relay, descripcion)
SELECT DISTINCT 
    d.id, 
    d.descripcion, 
    -- Intentamos recuperar su IP de gestión real de la propiedad 3 del legacy
    COALESCE(
        (SELECT valor::inet FROM legacy_import.tec_dispositivos_propiedades_dispositivos 
         WHERE id_dispositivo = d.id AND id_propiedad = 3 AND valor ~ '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' LIMIT 1),
        '10.20.100.1'::inet
    ) AS ip_relay,
    d.descripcion
FROM legacy_import.tec_dispositivos d
WHERE d.id IN (
    SELECT DISTINCT (valor::int) 
    FROM legacy_import.tec_dispositivos_propiedades_dispositivos 
    WHERE id_propiedad = 1009 AND valor ~ '^[0-9]+$'
)
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, ip_relay = EXCLUDED.ip_relay;

COMMIT;

-- =============================================================================
-- PARTE 3: CREACIÓN DE LA FUNCIÓN DE MIGRACIÓN DINÁMICA POR CMTS (Fase 2)
-- =============================================================================

CREATE OR REPLACE FUNCTION admin.migrar_datos_por_cmts(p_target_cmts_id INT)
RETURNS TABLE (
    resultado_mensaje TEXT,
    clientes_migrados INT,
    equipos_migrados INT,
    servicios_migrados INT
) AS $$
DECLARE
    v_cmts_exists INT;
    v_count_clientes INT := 0;
    v_count_equipos INT := 0;
    v_count_servicios INT := 0;
    v_cmts_name TEXT;
BEGIN
    -- 1. Verificar si el CMTS objetivo existe en nuestro catálogo de la DB nueva
    SELECT COUNT(*), MAX(nombre) INTO v_cmts_exists, v_cmts_name 
    FROM admin.cmts WHERE id = p_target_cmts_id;
    
    IF v_cmts_exists = 0 THEN
        RETURN QUERY SELECT 
            CONCAT('ERROR: El CMTS con ID ', p_target_cmts_id, ' no existe en el catálogo. Corre la Fase 1 primero.') AS resultado_mensaje,
            0, 0, 0;
        RETURN;
    END IF;

    -- 2. Desactivar temporalmente los triggers de sincronización Kea para evitar demoras transaccionales
    ALTER TABLE admin.servicios_clientes DISABLE TRIGGER trg_sync_servicio_to_kea_hosts;

    -- 3. MIGRACIÓN FASE 1: CLIENTES ACTIVOS E INVOLUCRADOS EN ESTE CMTS
    -- Se migran solo clientes que tengan servicios de cablemódem activos o suspendidos en este CMTS
    INSERT INTO admin.clientes (id, razon_social, cuit_dni, telefono, email, calle, altura, id_localidad, codigo, latitud, longitud, direccion)
    SELECT DISTINCT
        c.id,
        COALESCE(NULLIF(TRIM(c.responsable), ''), c.denominacion),
        -- Normalizamos DNI/CUIT colocándole su ID de cliente como fallback ante datos vacíos
        COALESCE(NULLIF(regexp_replace(c.nro_documento, '[^0-9]', '', 'g'), ''), c.id::text) AS cuit_dni,
        COALESCE(c.telefono_movil, c.telefono) AS telefono,
        c.email_contacto,
        l.calle,
        l.numero,
        l.id_localidad,
        c.denominacion, -- Código de Facturación original del cliente
        l.latitud,
        l.longitud,
        CONCAT(l.calle, ' ', l.numero, ', ', loc.nombre)
    FROM legacy_import.com_clientes c
    JOIN legacy_import.com_locaciones_clientes l ON l.id_cliente = c.id
    JOIN legacy_import.com_localidades loc ON l.id_localidad = loc.id
    -- Vinculamos con los paquetes y servicios para asegurar pertenencia a este CMTS
    JOIN legacy_import.com_locaciones_clientes_packs lcp ON lcp.id_locacion_cliente = l.id
    JOIN legacy_import.com_locaciones_clientes_packs_servicios lcps ON lcps.id_locacion_cliente_pack = lcp.id
    JOIN legacy_import.svc_servicios_propiedades sp_cm ON sp_cm.id_locacion_cliente_pack_servicio = lcps.id AND sp_cm.id_propiedad = 1003
    JOIN legacy_import.tec_dispositivos_propiedades_dispositivos dp ON dp.id_dispositivo = sp_cm.valor::int AND dp.id_propiedad = 1009
    WHERE dp.valor::int = p_target_cmts_id
    ON CONFLICT (id) DO NOTHING;
    
    GET DIAGNOSTICS v_count_clientes = ROW_COUNT;

    -- 4. MIGRACIÓN FASE 2: EQUIPAMIENTO ASOCIADO (Cablemódems activos en este CMTS)
    -- Extraemos la dirección MAC física y el número de serie limpiando duplicados genéricos
    INSERT INTO admin.equipos (id, id_modelo, mac, numero_serie, estado)
    WITH serial_counts AS (
        SELECT valor, count(*) as qty
        FROM legacy_import.tec_dispositivos_etiquetas_dispositivos
        WHERE id_etiqueta = 1001 AND valor IS NOT NULL AND TRIM(valor) <> ''
        GROUP BY valor
    )
    SELECT DISTINCT
        d.id,
        d.id_modelo,
        -- Lógica de formateo y casteo a MACADDR para cumplir la restricción rígida
        CAST(
            regexp_replace(
                lower(de_mac.valor), 
                '([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})', 
                '\1:\2:\3:\4:\5:\6'
            ) AS MACADDR
        ) AS mac,
        -- Si el número de serie es un placeholder genérico o está duplicado, se setea como NULL para respetar UNIQUE
        CASE 
            WHEN TRIM(de_serial.valor) IN ('', '0', '1', '111', '1234', '1111') THEN NULL
            WHEN sc.qty > 1 THEN NULL
            ELSE TRIM(de_serial.valor)
        END AS numero_serie,
        -- Mapeamos el estado real del cablemódem basado en la suscripción comercial del cliente
        COALESCE(
            (SELECT CASE WHEN lcp_sub.estado = 1 THEN 'ACTIVO'::VARCHAR ELSE 'SUSPENDIDO'::VARCHAR END
             FROM legacy_import.svc_servicios_propiedades sp_sub
             JOIN legacy_import.com_locaciones_clientes_packs_servicios lcps_sub ON lcps_sub.id = sp_sub.id_locacion_cliente_pack_servicio
             JOIN legacy_import.com_locaciones_clientes_packs lcp_sub ON lcp_sub.id = lcps_sub.id_locacion_cliente_pack
             WHERE sp_sub.id_propiedad = 1003 AND sp_sub.valor ~ '^[0-9]+$' AND sp_sub.valor::int = d.id LIMIT 1),
            'INVENTARIO'::VARCHAR
        ) AS estado
    FROM legacy_import.tec_dispositivos d
    -- Obtenemos el CMTS de la propiedad técnica 1009
    JOIN legacy_import.tec_dispositivos_propiedades_dispositivos dp ON dp.id_dispositivo = d.id AND dp.id_propiedad = 1009
    -- Obtenemos la dirección MAC real de la etiqueta de hardware HFC MAC (1002)
    JOIN legacy_import.tec_dispositivos_etiquetas_dispositivos de_mac ON de_mac.id_dispositivo = d.id AND de_mac.id_etiqueta = 1002
    -- Left join para traer el número de serie de la etiqueta de hardware 1001
    LEFT JOIN legacy_import.tec_dispositivos_etiquetas_dispositivos de_serial ON de_serial.id_dispositivo = d.id AND de_serial.id_etiqueta = 1001
    LEFT JOIN serial_counts sc ON sc.valor = de_serial.valor
    WHERE dp.valor::int = p_target_cmts_id 
      AND de_mac.valor ~ '^[0-9a-fA-F]{12}$' -- Evita cualquier cadena de texto inválida o mal cargada
    ON CONFLICT (mac) DO UPDATE SET 
        estado = EXCLUDED.estado,
        numero_serie = EXCLUDED.numero_serie;

    GET DIAGNOSTICS v_count_equipos = ROW_COUNT;

    -- 5. MIGRACIÓN FASE 3: SERVICIOS TÉCNICOS (Suscripciones técnicas)
    -- Asocia clientes, paquetes, equipos y CMTSs enlazando el estado comercial de la suscripción (1 = ACTIVO)
    INSERT INTO admin.servicios_clientes (id_cliente, id_equipo, id_paquete, id_cmts, ip_cm, ip_cpe, estado)
    SELECT DISTINCT
        l.id_cliente,
        eq.id AS id_equipo,
        -- Resolvemos dinámicamente el id del paquete por nombre para tolerar diferencias de ID en datos de prueba
        target_pack.id AS id_paquete,
        p_target_cmts_id AS id_cmts,
        NULL::inet AS ip_cm,
        -- IP CPE Estática (si la tuviera cargada en la propiedad 1004 del legacy)
        (SELECT valor::inet FROM legacy_import.svc_servicios_propiedades 
         WHERE id_locacion_cliente_pack_servicio = lcps.id AND id_propiedad = 1004 AND valor ~ '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' LIMIT 1) AS ip_cpe,
        -- Mapeamos el estado real del pack (1 = ACTIVO comercialmente)
        CASE WHEN lcp.estado = 1 THEN 'ACTIVO' ELSE 'SUSPENDIDO' END AS estado
    FROM legacy_import.com_locaciones_clientes_packs_servicios lcps
    JOIN legacy_import.com_locaciones_clientes_packs lcp ON lcps.id_locacion_cliente_pack = lcp.id
    JOIN legacy_import.com_packs source_pack ON lcp.id_pack = source_pack.id
    -- Vinculamos con la tabla nueva cruzando por nombre único de plan
    JOIN admin.paquetes target_pack ON target_pack.nombre = source_pack.descripcion
    JOIN legacy_import.com_locaciones_clientes l ON lcp.id_locacion_cliente = l.id
    -- Obtenemos el Cablemódem asignado (propiedad 1003)
    JOIN legacy_import.svc_servicios_propiedades sp ON sp.id_locacion_cliente_pack_servicio = lcps.id AND sp.id_propiedad = 1003
    -- Validamos que el equipo exista ya en la tabla de equipos migrados para asegurar la FK
    JOIN admin.equipos eq ON eq.id = sp.valor::int
    -- Obtenemos el CMTS del Cablemódem (propiedad 1009)
    JOIN legacy_import.tec_dispositivos_propiedades_dispositivos dp ON dp.id_dispositivo = eq.id AND dp.id_propiedad = 1009
    WHERE dp.valor::int = p_target_cmts_id
    ON CONFLICT (id_equipo) DO NOTHING;

    GET DIAGNOSTICS v_count_servicios = ROW_COUNT;

    -- 6. Volver a activar los triggers de Kea
    ALTER TABLE admin.servicios_clientes ENABLE TRIGGER trg_sync_servicio_to_kea_hosts;

    RETURN QUERY SELECT 
        CONCAT('ÉXITO: Migración completada para el CMTS ', v_cmts_name, ' (ID: ', p_target_cmts_id, ')') AS resultado_mensaje,
        v_count_clientes,
        v_count_equipos,
        v_count_servicios;
END;
$$ LANGUAGE plpgsql;
