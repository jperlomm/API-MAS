-- Habilitar extensión para generación de UUIDs si no existe
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================================================================
-- 1. TABLA DE USUARIOS (Claves UUID, Throttling de Fuerza Bruta y Soft-Delete)
-- =========================================================================
CREATE TABLE IF NOT EXISTS admin.usuarios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    nombre_completo VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    rol VARCHAR(30) NOT NULL DEFAULT 'OPERADOR' CONSTRAINT chk_usuario_rol CHECK (rol IN ('ADMIN', 'OPERADOR', 'TECNICO')), -- 'ADMIN', 'OPERADOR', 'TECNICO'
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    
    -- Throttling contra Fuerza Bruta
    intentos_fallidos INT NOT NULL DEFAULT 0,
    bloqueado_hasta TIMESTAMP WITH TIME ZONE NULL,
    
    fecha_creacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    fecha_modificacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indices para búsquedas ultra-rápidas en el Login
CREATE INDEX IF NOT EXISTS idx_usuarios_username ON admin.usuarios(username);

-- =========================================================================
-- 2. TOKENS DE REFRESCO (Persistencia de Refresh Tokens para Silent Refresh)
-- =========================================================================
CREATE TABLE IF NOT EXISTS admin.user_refresh_tokens (
    id SERIAL PRIMARY KEY,
    usuario_id UUID NOT NULL REFERENCES admin.usuarios(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    fecha_expiracion TIMESTAMP WITH TIME ZONE NOT NULL,
    creado_desde_ip VARCHAR(45) NULL,
    revocado BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_creacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_token_hash ON admin.user_refresh_tokens(token_hash);

-- =========================================================================
-- 3. LOGS DE AUDITORÍA (Historial de accesos y auditoría de eventos)
-- =========================================================================
CREATE TABLE IF NOT EXISTS admin.logs_autenticacion (
    id BIGSERIAL PRIMARY KEY,
    usuario_id UUID NULL REFERENCES admin.usuarios(id) ON DELETE SET NULL,
    username_ingresado VARCHAR(50) NOT NULL,
    ip_origen VARCHAR(45) NOT NULL,
    user_agent VARCHAR(255) NOT NULL,
    exitoso BOOLEAN NOT NULL,
    detalles VARCHAR(150) NULL,
    fecha TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_logs_auth_fecha ON admin.logs_autenticacion(fecha);

-- =========================================================================
-- Seed: Administrador Inicial (Username: admin, Password: adminpassword123)
-- Hash BCrypt generado para 'adminpassword123'
-- =========================================================================
INSERT INTO admin.usuarios (username, password_hash, nombre_completo, email, rol, activo)
VALUES (
    'admin',
    '$2a$11$9GscdFjPZ6WJv8K1m7nFeebfQ1oVlYh6zM2N3aR4sT5uV6wXxYyZ.',
    'Administrador del Sistema',
    'admin@spi-network.net',
    'ADMIN',
    TRUE
)
ON CONFLICT (username) DO NOTHING;

-- =========================================================================
-- 4. CONTROL DE DIRECCIONAMIENTO E IPAM (Reservas Temporales y Unicidad de IPs)
-- =========================================================================

-- Tabla técnica ligera para pre-arrendamientos asíncronos en la Web UI
CREATE TABLE IF NOT EXISTS admin.ip_reservas_temporales (
    ip INET PRIMARY KEY,
    subred_id INT NOT NULL REFERENCES admin.subredes(id) ON DELETE CASCADE,
    operador_id UUID NOT NULL REFERENCES admin.usuarios(id) ON DELETE CASCADE,
    fecha_expiracion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() + INTERVAL '5 minutes')
);

-- Índices Únicos Parciales para garantizar blindaje absoluto contra colisiones
CREATE UNIQUE INDEX IF NOT EXISTS uq_servicios_clientes_ip_cpe 
ON admin.servicios_clientes(ip_cpe) 
WHERE ip_cpe IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_servicios_clientes_ip_cm 
ON admin.servicios_clientes(ip_cm) 
WHERE ip_cm IS NOT NULL;

-- Función de búsqueda secuencial optimizada O(N log N) para descubrir IPs libres
CREATE OR REPLACE FUNCTION admin.get_next_free_ip(
    p_subred_id INT, 
    p_operador_id UUID DEFAULT NULL,
    p_id_paquete INT DEFAULT NULL
)
RETURNS INET AS $$
DECLARE
    v_ip INET;
    v_rango_inicio INET;
    v_rango_fin INET;
    v_cidr CIDR;
    v_gateway INET;
BEGIN
    -- 1. Limpieza inline de reservas expiradas
    DELETE FROM admin.ip_reservas_temporales WHERE fecha_expiracion < NOW();

    -- 2. Obtener datos de la subred para exclusión
    SELECT cidr, gateway INTO v_cidr, v_gateway
    FROM admin.subredes
    WHERE id = p_subred_id;

    -- 3. Obtener el pool reservado de la clase DHCP del plan de manera directa
    SELECT rango_inicio, rango_fin INTO v_rango_inicio, v_rango_fin
    FROM admin.pools p
    WHERE p.id_subred = p_subred_id 
      AND (
        (
          p_id_paquete IS NOT NULL 
          AND p.client_class = (SELECT dhcp4_client_class FROM admin.paquetes WHERE id = p_id_paquete)
        )
        OR 
        (p_id_paquete IS NULL AND p.client_class IS NULL)
      )
    ORDER BY COALESCE(p.es_estatico, FALSE) DESC, p.id
    LIMIT 1;

    IF v_rango_inicio IS NULL THEN
        RETURN NULL;
    END IF;

    -- 4. Algoritmo de detección de huecos secuenciales O(N log N)
    WITH occupied AS (
        SELECT ip_cpe AS ip FROM admin.servicios_clientes 
        WHERE ip_cpe >= v_rango_inicio AND ip_cpe <= v_rango_fin
        UNION
        SELECT ip_cm FROM admin.servicios_clientes 
        WHERE ip_cm >= v_rango_inicio AND ip_cm <= v_rango_fin
        UNION
        SELECT ip FROM admin.ip_reservas_temporales 
        WHERE subred_id = p_subred_id AND fecha_expiracion > NOW()
    )
    SELECT COALESCE(
        -- Caso A: El inicio del rango está disponible
        (
            SELECT v_rango_inicio 
            WHERE NOT EXISTS (SELECT 1 FROM occupied WHERE ip = v_rango_inicio)
              AND v_rango_inicio <> network(v_cidr)::inet
              AND v_rango_inicio <> broadcast(v_cidr)::inet
              AND v_rango_inicio <> v_gateway
        ),
        -- Caso B: El primer hueco secuencial libre (+1) posterior a una IP ocupada
        (
            SELECT MIN(o.ip + 1)
            FROM occupied o
            WHERE (o.ip + 1) <= v_rango_fin
              AND (o.ip + 1) <> network(v_cidr)::inet
              AND (o.ip + 1) <> broadcast(v_cidr)::inet
              AND (o.ip + 1) <> v_gateway
              AND NOT EXISTS (SELECT 1 FROM occupied o2 WHERE o2.ip = o.ip + 1)
        )
    ) INTO v_ip;

    -- 5. Si viene de UI (p_operador_id no nulo), registrar el bloqueo temporal de 5 minutos
    IF v_ip IS NOT NULL AND p_operador_id IS NOT NULL THEN
        INSERT INTO admin.ip_reservas_temporales (ip, subred_id, operador_id)
        VALUES (v_ip, p_subred_id, p_operador_id);
    END IF;

    RETURN v_ip;
END;
$$ LANGUAGE plpgsql;

