# Plan de Migración e Integración de Datos (Legacy ➔ Nuevo Admin)

Este plan de diseño e implementación detalla el procedimiento técnico para migrar de forma progresiva y segura los datos de la base de datos antigua (definida en `create_table.sql`) hacia la nueva base de datos de administración del SPI (`admin` y `public` en PostgreSQL para Kea DHCP).

La migración se dividirá en dos fases clave:
1. **Fase de Catálogo Estático:** Migración de datos globales que rara vez cambian (Países, Provincias, Localidades, Marcas, Modelos, Planes Comerciales y descubrimiento automatizado de CMTSs).
2. **Fase Técnica Activa por CMTS:** Migración aislada de Clientes, Equipos y Suscripciones correspondientes a un único CMTS de prueba, seguido de su sincronización masiva con Kea DHCP de forma segura.

---

## User Review Required

> [!IMPORTANT]
> **Desactivación de Triggers durante la Migración:**
> Durante la importación de datos activos (`servicios_clientes`), el trigger `trg_sync_servicio_to_kea_hosts` debe ser **desactivado** temporalmente. Esto evita sobrecarga de procesamiento, bloqueos por dependencias transaccionales incompletas o fallos masivos por datos legados con errores de formato. Una vez finalizada la migración de un bloque, el trigger se reactiva y se ejecuta una sincronización en bloque de Kea.

> [!WARNING]
> **Formato de Dirección MAC:**
> En el sistema legacy, las MACs están guardadas como texto simple (a menudo sin dos puntos, ej: `e848b88dd509` o con formatos variables). La nueva tabla `admin.equipos.mac` requiere estrictamente el tipo `MACADDR` de Postgres (ej: `e8:48:b8:8d:d5:09`). El script de migración incluye lógica para reformatear y normalizar las MACs antes de la inserción usando expresiones regulares o funciones Postgres.

---

## Open Questions

> [!NOTE]
> No hay preguntas bloqueantes en este momento, pero es importante que el usuario valide si el ID del CMTS que usaremos para la prueba de migración inicial es el correcto y si se aplicarán velocidades por defecto (ej: 50 Mbps de bajada / 10 Mbps de subida) a aquellos planes que no tengan velocidades explícitas en el legacy.

---

## Contenedor de Base de Datos Legacy de Solo Lectura (Aislado)

Para realizar tus pruebas de migración y auditoría de forma 100% segura, libre de riesgos y totalmente aislada de la base de datos actual de desarrollo/producción, proponemos levantar un contenedor temporal de PostgreSQL mapeado a un puerto secundario (por ejemplo, el puerto **`5435`**):

### 1. Iniciar el Contenedor Docker Temporal
Montamos el directorio donde reside tu dump comprimido (`spi40db.dump.gz`) directamente en la carpeta `/backup` del contenedor para que sea accesible:

```bash
docker run --name pg_legacy_temp \
  -e POSTGRES_DB=spi_legacy \
  -e POSTGRES_PASSWORD=P0stgr3s_legacy_pwd \
  -p 5435:5432 \
  -v "/home/usuario/Documentos/antigravity/SPI-V1/POSTREGRES LEGACY/":/backup \
  -d postgres:15
```

### 2. Restaurar el Dump de Base de Datos (`spi40db.dump.gz`)
Dependiendo de cómo se haya generado el dump en el sistema antiguo, puedes restaurarlo usando una de estas dos opciones (pruébalas en este orden):

* **Opción A (Si el dump es texto SQL plano comprimido con gzip):**
  ```bash
  docker exec -i pg_legacy_temp bash -c "gunzip -c /backup/spi40db.dump.gz" | docker exec -i pg_legacy_temp psql -U postgres -d spi_legacy
  ```

* **Opción B (Si el dump es de formato binario custom de pg_dump -Fc comprimido):**
  ```bash
  docker exec -it pg_legacy_temp pg_restore -U postgres -d spi_legacy /backup/spi40db.dump.gz
  ```

### 3. Conexión y Pruebas
Una vez restaurada, podrás conectarte de forma segura desde cualquier herramienta de base de datos (DBeaver, pgAdmin, o `psql`) usando:
* **Host:** `localhost` o `127.0.0.1`
* **Puerto:** `5435`
* **Base de Datos:** `spi_legacy`
* **Usuario:** `postgres`
* **Contraseña:** `P0stgr3s_legacy_pwd`

Cuando hayas completado todas tus pruebas de migración y consultas, puedes destruir el contenedor temporal de forma sumamente simple sin dejar residuos en tu sistema:
```bash
docker rm -f pg_legacy_temp
```

---

## Proposed Changes

Proponemos la creación de tres scripts SQL que se guardarán en el directorio de scratch o de base de datos para su fácil ejecución secuencial en PostgreSQL.

### [Componente: Migración de Base de Datos (Scripts SQL)]

#### [NEW] [01_migracion_catalogos_estaticos.sql](file:///home/usuario/Documentos/antigravity/SPI-V1/spi/postgres/01_migracion_catalogos_estaticos.sql)
Script encargado de migrar toda la infraestructura base geográfica y de catálogo técnico de hardware/planes.

#### [NEW] [02_migracion_dinamica_por_cmts.sql](file:///home/usuario/Documentos/antigravity/SPI-V1/spi/postgres/02_migracion_dinamica_por_cmts.sql)
Script parametrizado que migra la porción de red y abonados de un único CMTS específico.

#### [NEW] [03_sincronizacion_kea.sql](file:///home/usuario/Documentos/antigravity/SPI-V1/spi/postgres/03_sincronizacion_kea.sql)
Script que reactiva los triggers y sincroniza en lote (bulk insert) todos los nuevos servicios migrados hacia la base de datos activa de Kea DHCP.

---

## Detalle Técnico de los Scripts SQL Propuestos

### 1. Script de Catálogos Estáticos (`01_migracion_catalogos_estaticos.sql`)

Este script se encarga de poblar las tablas maestras iniciales de geografía, hardware, paquetes comerciales y el autodescubrimiento de los CMTSs referenciados por las zonas.

```sql
-- =========================================================================
-- FASE 1: MIGRACIÓN DE CATÁLOGOS ESTÁTICOS GENERALES
-- =========================================================================
BEGIN;

-- 1. Países, Provincias y Localidades
INSERT INTO admin.paises (id, nombre)
SELECT id, nombre FROM public.com_paises
ON CONFLICT (id) DO NOTHING;

INSERT INTO admin.provincias (id, nombre, id_pais)
SELECT id, nombre, id_pais FROM public.com_provincias
ON CONFLICT (id) DO NOTHING;

INSERT INTO admin.localidades (id, nombre, id_provincia)
SELECT id, nombre, id_provincia FROM public.com_localidades
ON CONFLICT (id) DO NOTHING;

-- 2. Marcas y Modelos de Hardware
INSERT INTO admin.marcas (id, nombre)
SELECT id, nombre FROM public.tec_marcas
ON CONFLICT (id) DO NOTHING;

INSERT INTO admin.modelos (id, id_marca, nombre, tipo, descripcion)
SELECT 
    id, 
    id_marca, 
    descripcion, 
    CASE WHEN id_tipo_dispositivo = 1000 THEN 'DOCSIS' ELSE 'GPON' END AS tipo,
    descripcion
FROM public.tec_modelos
ON CONFLICT (id) DO NOTHING;

-- 3. Autodescubrimiento y Alta de CMTSs
-- Buscamos los dispositivos que son referenciados como CMTS de cablemódems en la propiedad técnica 1009
INSERT INTO admin.cmts (id, nombre, ip_relay, descripcion)
SELECT DISTINCT 
    d.id, 
    d.descripcion, 
    -- Intentamos obtener su IP de gestión real de la propiedad 3, de lo contrario usamos fallback
    COALESCE(
        (SELECT valor::inet FROM public.tec_dispositivos_propiedades_dispositivos 
         WHERE id_dispositivo = d.id AND id_propiedad = 3 AND valor ~ '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' LIMIT 1),
        '10.20.100.1'::inet
    ) AS ip_relay,
    d.descripcion
FROM public.tec_dispositivos d
WHERE d.id IN (
    SELECT DISTINCT (valor::int) 
    FROM public.tec_dispositivos_propiedades_dispositivos 
    WHERE id_propiedad = 1009 AND valor ~ '^[0-9]+$'
)
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, ip_relay = EXCLUDED.ip_relay;

-- 4. Planes Comerciales (Paquetes)
INSERT INTO admin.paquetes (id, nombre, velocidad_bajada_kbps, velocidad_subida_kbps, bootfile, dhcp4_client_class)
SELECT 
    id, 
    descripcion, 
    50000 AS velocidad_bajada_kbps, -- Velocidad por defecto (50 Mbps)
    10000 AS velocidad_subida_kbps, -- Velocidad por defecto (10 Mbps)
    'default.bin' AS bootfile,
    'cpe-dhcp-nat' AS dhcp4_client_class
FROM public.com_packs
ON CONFLICT (id) DO NOTHING;

COMMIT;
```

---

### 2. Script de Migración Dinámica por CMTS (`02_migracion_dinamica_por_cmts.sql`)

Este script utiliza una función de Postgres (PL/pgSQL) para encapsular la lógica de migración de forma segura, permitiendo migrar **únicamente un CMTS por vez** pasando su ID como parámetro.

```sql
-- =========================================================================
-- FASE 2: MIGRACIÓN SEGMENTADA POR CMTS (PARAMETRIZADO)
-- =========================================================================
CREATE OR REPLACE FUNCTION admin.migrar_datos_por_cmts(p_target_cmts_id INT)
RETURNS VOID AS $$
DECLARE
    v_count_clientes INT := 0;
    v_count_equipos INT := 0;
    v_count_servicios INT := 0;
BEGIN
    RAISE NOTICE 'Iniciando migración para el CMTS ID: %', p_target_cmts_id;

    -- 0. Desactivar temporalmente los triggers para evitar colisiones y sobrecarga en Kea
    ALTER TABLE admin.servicios_clientes DISABLE TRIGGER trg_sync_servicio_to_kea_hosts;

    -- 1. Migrar Clientes pertenecientes a las zonas de este CMTS
    INSERT INTO admin.clientes (id, razon_social, cuit_dni, telefono, email, calle, altura, id_localidad, codigo, latitud, longitud, direccion)
    SELECT DISTINCT
        c.id,
        COALESCE(c.responsable, c.denominacion),
        -- Normalizamos DNI/CUIT y colocamos fallback por si es nulo (ej: ID del cliente) para evitar fallos de restricción
        COALESCE(NULLIF(regexp_replace(c.nro_documento, '[^0-9]', '', 'g'), ''), c.id::text),
        COALESCE(c.telefono_movil, c.telefono),
        c.email_contacto,
        l.calle,
        l.numero,
        l.id_localidad,
        c.denominacion, -- Código de Facturación original del cliente
        l.latitud,
        l.longitud,
        CONCAT(l.calle, ' ', l.numero, ', ', loc.nombre)
    FROM public.com_clientes c
    JOIN public.com_locaciones_clientes l ON l.id_cliente = c.id
    JOIN public.com_localidades loc ON l.id_localidad = loc.id
    -- Vinculamos comercialmente con los servicios de sus cablemódems asociados a este CMTS
    JOIN public.com_locaciones_clientes_packs lcp ON lcp.id_locacion_cliente = l.id
    JOIN public.com_locaciones_clientes_packs_servicios lcps ON lcps.id_locacion_cliente_pack = lcp.id
    JOIN public.svc_servicios_propiedades sp_cm ON sp_cm.id_locacion_cliente_pack_servicio = lcps.id AND sp_cm.id_propiedad = 1003
    JOIN public.tec_dispositivos_propiedades_dispositivos dp ON dp.id_dispositivo = sp_cm.valor::int AND dp.id_propiedad = 1009
    WHERE dp.valor::int = p_target_cmts_id
    ON CONFLICT (id) DO NOTHING;
    
    GET DIAGNOSTICS v_count_clientes = ROW_COUNT;
    RAISE NOTICE 'Fase Clientes completa. Registrados: %', v_count_clientes;

    -- 2. Migrar Equipamientos (Módems/CPEs asociados a este CMTS en la propiedad 1009)
    -- En el legacy, las MACs están guardadas en tec_dispositivos.descripcion
    INSERT INTO admin.equipos (id, id_modelo, mac, estado)
    SELECT DISTINCT
        d.id,
        d.id_modelo,
        -- Lógica de formateo y casteo a MACADDR para cumplir la restricción rígida
        CAST(
            regexp_replace(
                lower(d.descripcion), 
                '([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})', 
                '\1:\2:\3:\4:\5:\6'
            ) AS MACADDR
        ) AS mac,
        'INVENTARIO' -- Se migran en estado inventario temporalmente, luego el alta de servicios los pasa a ACTIVO
    FROM public.tec_dispositivos d
    JOIN public.tec_dispositivos_propiedades_dispositivos dp ON dp.id_dispositivo = d.id AND dp.id_propiedad = 1009
    WHERE dp.valor::int = p_target_cmts_id 
      AND d.descripcion ~ '^[0-9a-fA-F]{12}$' -- Asegura que sean MACs limpias de 12 caracteres hex
    ON CONFLICT (mac) DO NOTHING;

    GET DIAGNOSTICS v_count_equipos = ROW_COUNT;
    RAISE NOTICE 'Fase Equipos completa. Registrados: %', v_count_equipos;

    -- 3. Migrar Servicios/Suscripciones Técnicas Activas
    INSERT INTO admin.servicios_clientes (id_cliente, id_equipo, id_paquete, id_cmts, ip_cm, ip_cpe, estado)
    SELECT DISTINCT
        l.id_cliente,
        eq.id AS id_equipo,
        lcp.id_pack AS id_paquete,
        p_target_cmts_id AS id_cmts,
        -- IP de Gestión del Cablemódem (Opcional, si tiene fija o null)
        NULL::inet AS ip_cm,
        -- IP de Navegación del CPE (Extraída de la propiedad 1004 del legacy si existía)
        (SELECT valor::inet FROM public.svc_servicios_propiedades 
         WHERE id_locacion_cliente_pack_servicio = lcps.id AND id_propiedad = 1004 AND valor ~ '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' LIMIT 1) AS ip_cpe,
        -- En el legacy, el estado comercial del pack (lcp.estado = 1) representa el servicio ACTIVO
        CASE WHEN lcp.estado = 1 THEN 'ACTIVO' ELSE 'SUSPENDIDO' END AS estado
    FROM public.com_locaciones_clientes_packs_servicios lcps
    JOIN public.com_locaciones_clientes_packs lcp ON lcps.id_locacion_cliente_pack = lcp.id
    JOIN public.com_locaciones_clientes l ON lcp.id_locacion_cliente = l.id
    JOIN public.svc_servicios_propiedades sp ON sp.id_locacion_cliente_pack_servicio = lcps.id AND sp.id_propiedad = 1003
    -- Vinculamos con los equipos que acabamos de dar de alta en inventario para asegurar referencias
    JOIN admin.equipos eq ON eq.id = sp.valor::int
    -- Buscamos el CMTS asignado a ese cablemódem
    JOIN public.tec_dispositivos_propiedades_dispositivos dp ON dp.id_dispositivo = eq.id AND dp.id_propiedad = 1009
    WHERE dp.valor::int = p_target_cmts_id
    ON CONFLICT (id_equipo) DO NOTHING;

    GET DIAGNOSTICS v_count_servicios = ROW_COUNT;
    RAISE NOTICE 'Fase Servicios completa. Registrados: %', v_count_servicios;

    -- 4. Reactivar el trigger de sincronización
    ALTER TABLE admin.servicios_clientes ENABLE TRIGGER trg_sync_servicio_to_kea_hosts;

    RAISE NOTICE 'Migración de datos para el CMTS % completada con éxito.', p_target_cmts_id;
END;
$$ LANGUAGE plpgsql;
```

---

### 3. Script de Sincronización Masiva con Kea DHCP (`03_sincronizacion_kea.sql`)

Una vez migrado un CMTS, sincronizamos en bloque todos sus servicios activos para que Kea DHCP tenga registradas las reservas globales de inmediato.

```sql
-- =========================================================================
-- FASE 3: SINCRONIZACIÓN EN BLOQUE CON KEA DHCP (MIGRACIÓN RAPIDA)
-- =========================================================================
BEGIN;

-- 1. Limpieza de seguridad en la tabla de hosts de Kea para este CMTS
DELETE FROM public.hosts h
WHERE (h.user_context->>'cmts_id')::int = 5; -- Filtra por el ID del CMTS que migramos

-- 2. Bulk Insert de Cablemódems (Tipo 0 - MAC Address)
INSERT INTO public.hosts (dhcp_identifier, dhcp_identifier_type, dhcp4_subnet_id, ipv4_address, dhcp4_client_classes, dhcp4_boot_file_name, dhcp4_next_server, user_context)
SELECT 
    -- Convertimos la MAC a su representación binaria BYTEA requerida por Kea
    DECODE(replace(eq.mac::text, ':', ''), 'hex') AS dhcp_identifier,
    0 AS dhcp_identifier_type, -- hw-address (MAC)
    -- Buscamos la subred de tipo 'CM' asignada a este CMTS
    (SELECT s.id FROM admin.subredes s WHERE s.id_cmts = sc.id_cmts AND s.tipo = 'CM' LIMIT 1) AS dhcp4_subnet_id,
    CASE WHEN sc.ip_cm IS NOT NULL THEN (sc.ip_cm - '0.0.0.0'::inet) ELSE NULL END AS ipv4_address,
    'docsis_modems' AS dhcp4_client_classes,
    pq.bootfile AS dhcp4_boot_file_name,
    ('192.168.2.106'::inet - '0.0.0.0'::inet) AS dhcp4_next_server,
    jsonb_build_object(
        'tipo', 'Cablemodem',
        'servicio_id', sc.id,
        'cliente_id', sc.id_cliente,
        'cmts_id', sc.id_cmts
    ) AS user_context
FROM admin.servicios_clientes sc
JOIN admin.equipos eq ON sc.id_equipo = eq.id
JOIN admin.paquetes pq ON sc.id_paquete = pq.id
WHERE sc.id_cmts = 5 AND sc.estado = 'ACTIVO';

-- 3. Bulk Insert de CPEs (Tipo 4 - Option 82 Remote-ID)
INSERT INTO public.hosts (dhcp_identifier, dhcp_identifier_type, dhcp4_subnet_id, ipv4_address, dhcp4_client_classes, user_context)
SELECT 
    -- El identificador en Kea DHCP para CPEs bajo Option 82 es la MAC del Cablemódem en formato binario
    DECODE(replace(eq.mac::text, ':', ''), 'hex') AS dhcp_identifier,
    4 AS dhcp_identifier_type, -- flex-id (Option 82 Remote-ID)
    -- Buscamos la subred de tipo 'CPE' asignada a este CMTS
    (SELECT s.id FROM admin.subredes s WHERE s.id_cmts = sc.id_cmts AND s.tipo = 'CPE' LIMIT 1) AS dhcp4_subnet_id,
    CASE WHEN sc.ip_cpe IS NOT NULL THEN (sc.ip_cpe - '0.0.0.0'::inet) ELSE NULL END AS ipv4_address,
    pq.dhcp4_client_class AS dhcp4_client_classes,
    jsonb_build_object(
        'tipo', 'CPE',
        'servicio_id', sc.id,
        'cliente_id', sc.id_cliente,
        'cmts_id', sc.id_cmts
    ) AS user_context
FROM admin.servicios_clientes sc
JOIN admin.equipos eq ON sc.id_equipo = eq.id
JOIN admin.paquetes pq ON sc.id_paquete = pq.id
WHERE sc.id_cmts = 5 AND sc.estado = 'ACTIVO';

-- 4. Inyectar opciones de bootfile en Kea DHCP para los módems activos
INSERT INTO public.dhcp4_options (code, value, formatted_value, space, scope_id, host_id, persistent)
SELECT 
    67 AS code,
    pq.bootfile::bytea AS value,
    pq.bootfile AS formatted_value,
    'dhcp4' AS space,
    3 AS scope_id, -- scope Host
    h.host_id,
    true AS persistent
FROM admin.servicios_clientes sc
JOIN admin.paquetes pq ON sc.id_paquete = pq.id
JOIN admin.equipos eq ON sc.id_equipo = eq.id
-- Cruzamos con la tabla hosts de Kea recién poblada para obtener los host_id
JOIN public.hosts h ON h.dhcp_identifier = DECODE(replace(eq.mac::text, ':', ''), 'hex') AND h.dhcp_identifier_type = 0
WHERE sc.id_cmts = 5 AND sc.estado = 'ACTIVO';

COMMIT;
```

---

## Verification Plan

### Automated Tests
Para verificar el funcionamiento de las migraciones, podemos realizar las siguientes consultas de diagnóstico en PostgreSQL:

* **Control de consistencia del catálogo estático:**
  ```sql
  SELECT COUNT(*) FROM admin.paises;
  SELECT COUNT(*) FROM admin.modelos;
  SELECT id, nombre, ip_relay FROM admin.cmts;
  ```

* **Control de carga del CMTS de prueba (ej: ID 5):**
  ```sql
  SELECT COUNT(*) FROM admin.clientes;
  SELECT COUNT(*) FROM admin.equipos WHERE estado = 'ACTIVO';
  SELECT id_cliente, id_equipo, ip_cpe, estado FROM admin.servicios_clientes WHERE id_cmts = 5;
  ```

* **Control de sincronización con Kea DHCP:**
  ```sql
  SELECT host_id, ipv4_address, dhcp4_subnet_id, dhcp4_client_classes, user_context 
  FROM public.hosts 
  WHERE (user_context->>'cmts_id')::int = 5;
  ```

### Manual Verification
1. Realizar una consulta fuzzy search mediante la API REST en el puerto `5152`:
   `GET /api/clientes/search?query=ABO` para comprobar si los clientes migrados figuran de forma inmediata y en los formatos correctos en el backend.
2. Comprobar que Kea DHCP lee correctamente las nuevas reservas globales reiniciando un cablemódem de prueba que esté conectado físicamente al CMTS migrado.
