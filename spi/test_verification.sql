-- =========================================================================
-- SCRIPT DE PRUEBA Y VERIFICACION - SINCRO KEA DHCP EN TIEMPO REAL
-- =========================================================================
-- Ejecutar en psql una vez levantada la base de datos limpia para probar el trigger.
-- Comando: psql -U postgres -d dhcp -f test_verification.sql

BEGIN;

\echo '------------------------------------------------------------'
\echo '1. CONFIGURANDO CATALOGO INICIAL (Marcas, Modelos, CMTS, Subredes y Pools)'
\echo '------------------------------------------------------------'

-- Insertar Marca y Modelo
INSERT INTO admin.marcas (id, nombre) VALUES (100, 'Cisco-Prueba');
INSERT INTO admin.modelos (id, id_marca, nombre, tipo, descripcion) 
VALUES (100, 100, 'DPC3928-Prueba', 'DOCSIS', 'Módem de laboratorio');

-- Insertar CMTS
INSERT INTO admin.cmts (id, nombre, ip_relay, descripcion) 
VALUES (100, 'CMTS-MKT-Prueba', '10.20.100.1', 'CMTS de Pruebas de Laboratorio');

-- Insertar Subredes (CM y CPE)
INSERT INTO admin.subredes (id, id_cmts, nombre, cidr, gateway, tipo)
VALUES 
  (100, 100, 'CM-Gestion-Prueba', '10.20.100.0/22', '10.20.100.1', 'CM'),
  (101, 100, 'CPE-Navegacion-Prueba', '172.18.110.0/23', '172.18.110.1', 'CPE');

-- Insertar Paquete Comercial con Bootfile y Clase DHCP de velocidad
INSERT INTO admin.paquetes (id, nombre, velocidad_bajada_kbps, velocidad_subida_kbps, bootfile, dhcp4_client_class)
VALUES (100, 'Plan-Prueba-100M', 100000, 10000, 'cm-fil-100M-10Md11-TEST.bin', 'cpe-100M-10M-TEST-CLASS');

-- Insertar Pools DHCP en las Subredes
INSERT INTO admin.pools (id, id_subred, rango_inicio, rango_fin, id_paquete)
VALUES 
  (100, 100, '10.20.100.2', '10.20.103.254', NULL),        -- Pool dinámico para modems
  (101, 101, '172.18.110.2', '172.18.110.254', 100);       -- Pool dinámico de navegación para Plan de 100M

-- Insertar Cliente
INSERT INTO admin.clientes (id, razon_social, cuit_dni, telefono, email, direccion)
VALUES (100, 'Juan Perez (Prueba Sincro)', '20-11111111-9', '12345678', 'test@test.com', 'Calle Falsa 123');

-- Insertar Equipo en el Inventario (Estado inicial INVENTARIO)
INSERT INTO admin.equipos (id, id_modelo, mac, numero_serie, estado)
VALUES (100, 100, '7c:b2:1b:a0:00:f6', 'SERIE-PRUEBA-999', 'INVENTARIO');


\echo '------------------------------------------------------------'
\echo '2. ALTA DE SUSCRIPCION COMERCIAL (Asociación en servicios_clientes)'
\echo '------------------------------------------------------------'

-- El operador asocia el cliente, equipo, plan y CMTS.
-- Definimos una IP de gestión para el Cablemódem (ip_cm) y dejamos ip_cpe en NULL para que navegue dinámicamente del pool.
INSERT INTO admin.servicios_clientes (id, id_cliente, id_equipo, id_paquete, id_cmts, ip_cm, ip_cpe, estado)
VALUES (100, 100, 100, 100, 100, '10.20.100.45', NULL, 'ACTIVO');


\echo '------------------------------------------------------------'
\echo '3. CONSULTANDO TABLAS DE KEA DHCP (Verificación de Sincronización)'
\echo '------------------------------------------------------------'

\echo '>>> Reservaciones en la tabla hosts (deben figurar 2 filas: Cablemódem Tipo 0 y CPE Tipo 5):'
SELECT 
    host_id,
    ENCODE(dhcp_identifier, 'hex') AS mac_hex,
    CASE dhcp_identifier_type
        WHEN 0 THEN '0 (Cablemodem por MAC)'
        WHEN 5 THEN '5 (Router CPE por Option 82)'
    END AS tipo_reserva,
    '0.0.0.0'::inet + ipv4_address AS ip_reservada,
    dhcp4_client_classes AS clase_dhcp,
    user_context->>'tipo' AS context_tipo
FROM public.hosts;

\echo '>>> Opciones inyectadas (debe figurar el bootfile DOCSIS (opción 67) amarrado al host del CM):'
SELECT 
    host_id AS host_id_kea,
    code AS option_code,
    formatted_value AS valor_bootfile,
    space
FROM public.dhcp4_options;

\echo '>>> Estado del equipo en nuestro inventario administrativo (debe figurar como ACTIVO):'
SELECT id, mac, estado FROM admin.equipos WHERE id = 100;


\echo '------------------------------------------------------------'
\echo '4. CAMBIO DE ESTADO: SUSPENSION DEL SERVICIO COMERCIAL'
\echo '------------------------------------------------------------'
-- El operador suspende el servicio comercial
UPDATE admin.servicios_clientes SET estado = 'SUSPENDIDO' WHERE id = 100;

\echo '>>> Reservaciones en Kea tras SUSPENDER (debe estar vacía para cortar la navegación/provisión):'
SELECT COUNT(*) AS cant_reservas_kea FROM public.hosts;

\echo '>>> Opciones en Kea tras SUSPENDER (debe estar vacía para limpiar memoria):'
SELECT COUNT(*) AS cant_opciones_kea FROM public.dhcp4_options;

\echo '>>> Estado del equipo en nuestro inventario (debe figurar como SUSPENDIDO):'
SELECT id, mac, estado FROM admin.equipos WHERE id = 100;


\echo '------------------------------------------------------------'
\echo '5. BAJA COMPLETA DEL SERVICIO (Eliminación del contrato)'
\echo '------------------------------------------------------------'
-- Se rescinde el contrato y se elimina el servicio
DELETE FROM admin.servicios_clientes WHERE id = 100;

\echo '>>> Estado del equipo en nuestro inventario (debe figurar liberado como INVENTARIO):'
SELECT id, mac, estado FROM admin.equipos WHERE id = 100;


-- Hacemos ROLLBACK para no dejar basura de pruebas en la base de datos de producción
ROLLBACK;
\echo '------------------------------------------------------------'
\echo 'PRUEBA FINALIZADA CORRECTAMENTE (ROLLBACK REALIZADO)'
\echo '------------------------------------------------------------'
