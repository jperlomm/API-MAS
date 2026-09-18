-- =========================================================================
-- SPI V1.4 - SCRIPT DE PRUEBA Y VALIDACIÓN EN CALIENTE DE BASE DE DATOS
-- =========================================================================
-- Ejecutar estas consultas secuencialmente después de aplicar la migración
-- para comprobar que las restricciones están activas y blindando el sistema.
-- =========================================================================

-- -------------------------------------------------------------------------
-- PRUEBA 1: VALIDACIÓN DE RESTRICCIONES GEOGRÁFICAS (DEBE FALLAR)
-- -------------------------------------------------------------------------
-- Explicación: Intentamos borrar el País ID 1. Dado que tiene provincias
-- asociadas, PostgreSQL DEBE abortar la transacción con un error de violación.
-- -------------------------------------------------------------------------
BEGIN;
SELECT 'Ejecutando Prueba 1: Borrado Geográfico con RESTRICT...' AS paso;

-- Intentar borrar el País ID 1 (ej. Argentina)
DELETE FROM admin.paises WHERE id = 1;

-- Si llega aquí, es porque falló la restricción (MAL)
ROLLBACK;


-- -------------------------------------------------------------------------
-- PRUEBA 2: HARDENING DE ROLES DE USUARIO (DEBE FALLAR)
-- -------------------------------------------------------------------------
-- Explicación: Intentamos insertar un usuario con un rol inválido ('INVITADO').
-- PostgreSQL DEBE abortar la transacción debido a la restricción CHECK.
-- -------------------------------------------------------------------------
BEGIN;
SELECT 'Ejecutando Prueba 2: Hardening de Roles de Usuario...' AS paso;

INSERT INTO admin.usuarios (username, password_hash, nombre_completo, email, rol)
VALUES ('test_hacker', 'hash', 'Hacker de Prueba', 'test@hacker.com', 'INVITADO');

-- Si llega aquí, falló la restricción (MAL)
ROLLBACK;


-- -------------------------------------------------------------------------
-- PRUEBA 3: PREVENCIÓN DE TRASLAPES DE POOLS EN LA MISMA SUBRED (DEBE FALLAR)
-- -------------------------------------------------------------------------
-- Explicación: Buscamos un pool existente para usar su subred.
-- Luego intentamos crear un nuevo pool con un rango de IPs que se traslape.
-- El trigger 'trg_check_pool_overlap' DEBE detectar el traslape y denegar la inserción.
-- -------------------------------------------------------------------------
BEGIN;
SELECT 'Ejecutando Prueba 3: Prevención de Traslapes de Pools (IPAM)...' AS paso;

-- Intentar insertar un pool que se traslape con el rango de un pool existente
-- Nota: Suponemos que existe una subred con ID 2 (puedes cambiarlo por un ID válido)
-- con rango de IPs dinámicas como 172.250.2.8 - 172.250.2.9.
-- Si intentamos meter 172.250.2.9 - 172.250.2.15, debe colisionar en la IP .9.
INSERT INTO admin.pools (id_subred, rango_inicio, rango_fin, client_class)
VALUES (
    (SELECT id_subred FROM admin.pools LIMIT 1), 
    (SELECT rango_inicio FROM admin.pools LIMIT 1), 
    (SELECT rango_fin FROM admin.pools LIMIT 1), 
    'cpe-clase-test'
);

-- Si llega aquí, falló la restricción (MAL)
ROLLBACK;
