using System;
using System.Text;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using Microsoft.OpenApi.Models;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Configuration;
using Npgsql;
using FluentValidation;
using SmiApi.Services;
using SmiApi.Repositories;
using SmiApi.Validators;
using SmiApi.Middleware;
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

// =========================================================================
// 1. CONFIGURACIÓN DE BASE DE DATOS Y CONEXIONES (NpgSql)
// =========================================================================
var connectionString = Environment.GetEnvironmentVariable("DATABASE_URL") 
    ?? "Host=127.0.0.1;Database=dhcp;Username=postgres;Password=P0stgr3s";

builder.Services.AddSingleton(sp => new NpgsqlDataSourceBuilder(connectionString).Build());

// =========================================================================
// 2. CONFIGURACIÓN DE AUTENTICACIÓN JWT BEARER (.NET 8)
// =========================================================================
var jwtSettings = builder.Configuration.GetSection("Jwt");
var secret = jwtSettings["Secret"] ?? "SPI_Super_Secret_Core_Carrier_Class_Signature_Key_2026!";
var issuer = jwtSettings["Issuer"] ?? "spi-network.net";
var audience = jwtSettings["Audience"] ?? "spi-network.net";

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = issuer,
        ValidAudience = audience,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)),
        ClockSkew = TimeSpan.Zero // Control de expiración estricto (15 min reales)
    };
});

// =========================================================================
// 3. REGISTRO DE SERVICIOS Y REPOSITORIOS (Inyección de Dependencias)
// =========================================================================
builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<IAuthService, AuthService>();

// FluentValidation
builder.Services.AddValidatorsFromAssemblyContaining<LoginRequestValidator>();

// Servicios en segundo plano (Background Services / Workers)
builder.Services.AddSingleton<RebootQueueService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<RebootQueueService>());
builder.Services.AddHostedService<TokenCleanupBackgroundService>();
builder.Services.AddSingleton<KeaStatsService>();
builder.Services.AddHostedService<KeaStatsBackgroundService>();

// =========================================================================
// 4. CONTROLADORES, CORS Y SWAGGER
// =========================================================================
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
        options.JsonSerializerOptions.DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull;
    });

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo 
    { 
        Title = "SPI ISP Provisioning API (.NET 8)", 
        Version = "v1",
        Description = "API REST corporativa para la gestión de clientes, stock e inyección DHCP en tiempo real en Kea"
    });

    // Agregar soporte para pruebas de JWT en la UI de Swagger
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "Autorización JWT usando el esquema Bearer. Ejemplo: 'Bearer 12345abcdef'",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer"
    });

    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

var app = builder.Build();

// =========================================================================
// --- MIGRACIÓN AUTOMÁTICA DE BASE DE DATOS EN STARTUP ---
// =========================================================================
using (var scope = app.Services.CreateScope())
{
    var dataSource = scope.ServiceProvider.GetRequiredService<NpgsqlDataSource>();
    try
    {
        var adminPasswordHash = BCrypt.Net.BCrypt.HashPassword("adminpassword123", workFactor: 11);

        await using var cmd = dataSource.CreateCommand(@"
            -- Habilitar UUIDs
            CREATE EXTENSION IF NOT EXISTS ""uuid-ossp"";

            -- Esquema de Jerarquías Geográficas
            CREATE TABLE IF NOT EXISTS admin.paises (
                id SERIAL PRIMARY KEY,
                nombre VARCHAR(100) NOT NULL UNIQUE
            );

            CREATE TABLE IF NOT EXISTS admin.provincias (
                id SERIAL PRIMARY KEY,
                nombre VARCHAR(100) NOT NULL,
                id_pais INT NOT NULL REFERENCES admin.paises(id) ON DELETE CASCADE,
                CONSTRAINT uq_provincia_pais UNIQUE (nombre, id_pais)
            );

            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1 FROM information_schema.tables 
                    WHERE table_schema='admin' AND table_name='localidades'
                ) AND NOT EXISTS (
                    SELECT 1 FROM information_schema.columns 
                    WHERE table_schema='admin' AND table_name='localidades' AND column_name='id_provincia'
                ) THEN
                    ALTER TABLE admin.clientes DROP COLUMN IF EXISTS id_localidad CASCADE;
                    DROP TABLE admin.localidades CASCADE;
                END IF;
            END $$;

            CREATE TABLE IF NOT EXISTS admin.localidades (
                id SERIAL PRIMARY KEY,
                nombre VARCHAR(100) NOT NULL,
                id_provincia INT NOT NULL REFERENCES admin.provincias(id) ON DELETE CASCADE,
                CONSTRAINT uq_localidad_provincia UNIQUE (nombre, id_provincia)
            );

            -- Modificaciones en Clientes
            ALTER TABLE admin.clientes ADD COLUMN IF NOT EXISTS calle VARCHAR(150);
            ALTER TABLE admin.clientes ADD COLUMN IF NOT EXISTS altura VARCHAR(50);
            ALTER TABLE admin.clientes ADD COLUMN IF NOT EXISTS id_localidad INT REFERENCES admin.localidades(id) ON DELETE SET NULL;
            ALTER TABLE admin.clientes ADD COLUMN IF NOT EXISTS codigo VARCHAR(50) UNIQUE;
            ALTER TABLE admin.clientes ADD COLUMN IF NOT EXISTS latitud NUMERIC(10, 8);
            ALTER TABLE admin.clientes ADD COLUMN IF NOT EXISTS longitud NUMERIC(11, 8);
            ALTER TABLE admin.clientes DROP COLUMN IF EXISTS pais CASCADE;

            -- =================================================================
            -- TABLAS DE SEGURIDAD, USUARIOS Y AUDITORÍA (03_auth_schema)
            -- =================================================================
            CREATE TABLE IF NOT EXISTS admin.usuarios (
                id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                username VARCHAR(50) UNIQUE NOT NULL,
                password_hash VARCHAR(255) NOT NULL,
                nombre_completo VARCHAR(100) NOT NULL,
                email VARCHAR(100) UNIQUE NOT NULL,
                rol VARCHAR(30) NOT NULL DEFAULT 'OPERADOR',
                activo BOOLEAN NOT NULL DEFAULT TRUE,
                intentos_fallidos INT NOT NULL DEFAULT 0,
                bloqueado_hasta TIMESTAMP WITH TIME ZONE NULL,
                fecha_creacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
                fecha_modificacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS admin.user_refresh_tokens (
                id SERIAL PRIMARY KEY,
                usuario_id UUID NOT NULL REFERENCES admin.usuarios(id) ON DELETE CASCADE,
                token_hash VARCHAR(255) NOT NULL,
                fecha_expiracion TIMESTAMP WITH TIME ZONE NOT NULL,
                creado_desde_ip VARCHAR(45) NULL,
                revocado BOOLEAN NOT NULL DEFAULT FALSE,
                fecha_creacion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
            );

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

            -- Sembrar administrador inicial por defecto (actualizando la clave y desbloqueando)
            INSERT INTO admin.usuarios (username, password_hash, nombre_completo, email, rol, activo)
            VALUES (
                'admin',
                @admin_hash,
                'Administrador del Sistema',
                'admin@spi-network.net',
                'ADMIN',
                TRUE
            )
            ON CONFLICT (username) DO UPDATE 
            SET password_hash = EXCLUDED.password_hash,
                activo = TRUE,
                intentos_fallidos = 0,
                bloqueado_hasta = NULL;

            -- =================================================================
            -- CONTROL DE DIRECCIONAMIENTO E IPAM (Reservas Temporales y Unicidad de IPs)
            -- =================================================================
            CREATE TABLE IF NOT EXISTS admin.ip_reservas_temporales (
                ip INET PRIMARY KEY,
                subred_id INT NOT NULL REFERENCES admin.subredes(id) ON DELETE CASCADE,
                operador_id UUID NOT NULL REFERENCES admin.usuarios(id) ON DELETE CASCADE,
                fecha_expiracion TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() + INTERVAL '5 minutes')
            );

            -- =================================================================
            -- TELEMETRÍA HISTÓRICA DHCP (NOC)
            -- =================================================================
            CREATE TABLE IF NOT EXISTS admin.dhcp_hourly_stats (
                fecha TIMESTAMP WITH TIME ZONE PRIMARY KEY,
                discovers BIGINT NOT NULL DEFAULT 0,
                requests BIGINT NOT NULL DEFAULT 0,
                acks BIGINT NOT NULL DEFAULT 0,
                naks BIGINT NOT NULL DEFAULT 0,
                drops BIGINT NOT NULL DEFAULT 0
            );

            -- =================================================================
            -- CONFIGURACIONES GLOBALES DEL SISTEMA (V1.7)
            -- =================================================================
            CREATE TABLE IF NOT EXISTS admin.configuraciones (
                clave VARCHAR(100) PRIMARY KEY,
                valor TEXT NOT NULL,
                descripcion VARCHAR(200)
            );

            INSERT INTO admin.configuraciones (clave, valor, descripcion) VALUES
            ('telegram_bot_token', '', 'Token de la API de Bots de Telegram para alertas NOC'),
            ('telegram_chat_id', '', 'ID de Chat/Grupo de Telegram receptor de alertas NOC'),
            ('dhcp_lease_time', '86400', 'Tiempo de arrendamiento DHCP global (valid-lifetime) en segundos'),
            ('backup_retention_days', '7', 'Días de retención para copias de seguridad locales y remotas'),
            ('backup_remote_host', '192.168.2.X', 'Host o IP remota para duplicación de resguardos por SCP'),
            ('backup_remote_user', 'usuario', 'Usuario SSH para duplicación de resguardos remotos'),
            ('backup_remote_path', '/home/usuario/backups_spi', 'Directorio en servidor secundario para almacenar las réplicas'),
            ('isp_name', 'MMC', 'Nombre de fantasía de la empresa ISP')
            ON CONFLICT (clave) DO NOTHING;

            INSERT INTO admin.configuraciones (clave, valor, descripcion) VALUES
            ('infra_server_ip', '192.168.2.106', 'Dirección IP del servidor de infraestructura local para TFTP y ToD')
            ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor;

            -- Soportar múltiples domicilios agregando dirección de instalación al servicio
            ALTER TABLE admin.servicios_clientes ADD COLUMN IF NOT EXISTS direccion_instalacion VARCHAR(250);

            -- Soportar pools exclusivos para asignación estática/IPAM (que no se inyectan a Kea)
            ALTER TABLE admin.pools ADD COLUMN IF NOT EXISTS es_estatico BOOLEAN DEFAULT FALSE;

            -- Soportar vinculación de pools a Clases DHCP Kea directamente en lugar de a un único paquete
            ALTER TABLE admin.pools ADD COLUMN IF NOT EXISTS client_class VARCHAR(100) NULL;
            UPDATE admin.pools p SET client_class = (SELECT dhcp4_client_class FROM admin.paquetes WHERE id = p.id_paquete) WHERE p.client_class IS NULL AND p.id_paquete IS NOT NULL;

            -- Soportar bajas de servicios relajando las restricciones de integridad para mantener trazabilidad
            ALTER TABLE admin.historial_equipos_clientes ALTER COLUMN id_servicio DROP NOT NULL;
            ALTER TABLE admin.historial_equipos_clientes DROP CONSTRAINT IF EXISTS historial_equipos_clientes_id_servicio_fkey;
            ALTER TABLE admin.historial_equipos_clientes 
            ADD CONSTRAINT historial_equipos_clientes_id_servicio_fkey 
            FOREIGN KEY (id_servicio) REFERENCES admin.servicios_clientes(id) ON DELETE SET NULL;

            ALTER TABLE admin.historial_leases_ip DROP CONSTRAINT IF EXISTS historial_leases_ip_id_servicio_fkey;
            ALTER TABLE admin.historial_leases_ip 
            ADD CONSTRAINT historial_leases_ip_id_servicio_fkey 
            FOREIGN KEY (id_servicio) REFERENCES admin.servicios_clientes(id) ON DELETE SET NULL;

            CREATE UNIQUE INDEX IF NOT EXISTS uq_servicios_clientes_ip_cpe 
            ON admin.servicios_clientes(ip_cpe) 
            WHERE ip_cpe IS NOT NULL;

            CREATE UNIQUE INDEX IF NOT EXISTS uq_servicios_clientes_ip_cm 
            ON admin.servicios_clientes(ip_cm) 
            WHERE ip_cm IS NOT NULL;

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

            -- Limpiar la función duplicada creada por error anteriormente
            DROP FUNCTION IF EXISTS admin.sincronizar_kea_dhcp();

            -- Redefinir sync_servicio_to_kea_hosts con soporte para autodetección y pre-aprovisionamiento multi-subred dinámico
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
                v_rec RECORD;
                -- Variables para IP de servidor TFTP/ToD dinámica
                v_server_ip_str VARCHAR(100);
                v_server_ip_inet INET;
            BEGIN
                -- 0. Obtener la IP de infraestructura de forma dinámica desde la tabla de configuraciones
                SELECT valor INTO v_server_ip_str 
                FROM admin.configuraciones 
                WHERE clave = 'infra_server_ip' 
                LIMIT 1;
                
                -- Fallback de seguridad por si se elimina la clave por accidente
                v_server_ip_inet := COALESCE(v_server_ip_str, '192.168.2.106')::inet;

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

                -- 2. Limpieza de RESERVAS en public.hosts
                IF v_old_mac_bytes IS NOT NULL THEN
                    DELETE FROM public.hosts WHERE dhcp_identifier = v_old_mac_bytes;
                END IF;
                
                -- Limpieza de seguridad rápida y segura por texto en user_context para evitar excepciones de casteo JSON
                DELETE FROM public.hosts 
                WHERE user_context LIKE '%""servicio_id"": ' || COALESCE(OLD.id, NEW.id) || '%';

                -- 2.1 [SOPORTE INTELIGENTE DE LEASES]
                -- ÚNICAMENTE borramos leases si el servicio se elimina, se suspende, o si el hardware cambió físicamente.
                -- NO borramos leases en actualizaciones normales de CMTS (autodetección) ni en cambios de planes.
                IF (TG_OP = 'DELETE') OR (NEW.estado <> 'ACTIVO') THEN
                    -- Limpiar leases del equipo al desactivar o eliminar
                    IF v_old_mac_bytes IS NOT NULL THEN
                        DELETE FROM public.lease4 WHERE hwaddr = v_old_mac_bytes OR remote_id = v_old_mac_bytes;
                    END IF;
                ELSIF (TG_OP = 'UPDATE' AND OLD.id_equipo <> NEW.id_equipo) THEN
                    -- Limpiar leases del equipo anterior
                    IF v_old_mac_bytes IS NOT NULL THEN
                        DELETE FROM public.lease4 WHERE hwaddr = v_old_mac_bytes OR remote_id = v_old_mac_bytes;
                    END IF;
                    -- Limpieza preventiva del equipo nuevo para que inicie sin caché
                    IF v_new_mac_bytes IS NOT NULL THEN
                        DELETE FROM public.lease4 WHERE hwaddr = v_new_mac_bytes OR remote_id = v_new_mac_bytes;
                    END IF;
                END IF;

                -- 3. Manejo de Bajas o Suspensiones (Retorno temprano)
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

                -- [CMTS NULL - MULTI-SUBNET PRE-PROVISIONING]
                -- Si el CMTS es NULL, pre-creamos reservas temporales para todas las subredes CM/CPE activas del sistema.
                -- Esto permite que Kea resuelva la reserva en cualquier subred física donde encienda el módem.
                IF NEW.id_cmts IS NULL THEN
                    FOR v_rec IN 
                        SELECT s1.id as subnet_cm, s2.id as subnet_cpe, s1.id_cmts
                        FROM admin.subredes s1
                        LEFT JOIN admin.subredes s2 ON s2.id_cmts = s1.id_cmts AND s2.tipo = 'CPE'
                        WHERE s1.tipo = 'CM'
                    LOOP
                        -- Registrar Cablemodem (Tipo 0) de forma temporal para esta subred
                        INSERT INTO public.hosts (dhcp_identifier, dhcp_identifier_type, dhcp4_subnet_id, ipv4_address, dhcp4_client_classes, dhcp4_boot_file_name, dhcp4_next_server, user_context)
                        VALUES (
                            v_new_mac_bytes, 
                            0, 
                            v_rec.subnet_cm,
                            NULL, -- IP dinámica para autodetección
                            'docsis_modems',
                            v_bootfile,
                            (v_server_ip_inet - '0.0.0.0'::inet),
                            jsonb_build_object(
                                'tipo', 'Cablemodem',
                                'servicio_id', NEW.id,
                                'cliente_id', NEW.id_cliente,
                                'cmts_id', NULL -- Marcador de pre-aprovisionamiento
                            )
                        ) RETURNING host_id INTO v_host_id_cm;

                        -- Inyectar Opción 67 (Bootfile)
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

                        -- Registrar CPE (Tipo 4) de forma temporal para esta subred
                        IF v_rec.subnet_cpe IS NOT NULL THEN
                            INSERT INTO public.hosts (dhcp_identifier, dhcp_identifier_type, dhcp4_subnet_id, ipv4_address, dhcp4_client_classes, user_context)
                            VALUES (
                                v_new_mac_bytes, 
                                4, 
                                v_rec.subnet_cpe,
                                NULL, -- IP dinámica para autodetección
                                v_pack_class, 
                                jsonb_build_object(
                                    'tipo', 'CPE',
                                    'servicio_id', NEW.id,
                                    'cliente_id', NEW.id_cliente,
                                    'cmts_id', NULL -- Marcador de pre-aprovisionamiento
                                )
                            );
                        END IF;
                    END LOOP;

                    -- Actualizar el estado del equipo a ACTIVO
                    UPDATE admin.equipos SET estado = 'ACTIVO' WHERE id = NEW.id_equipo;
                    RETURN NEW;
                END IF;

                -- [CMTS DEFINITIVO - RESERVA FIJA ESTÁNDAR]
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

                -- Registrar Cablemodem (Tipo 0) definitivo
                v_ip_cm_int := CASE WHEN NEW.ip_cm IS NOT NULL THEN (NEW.ip_cm - '0.0.0.0'::inet) ELSE NULL END;
                
                INSERT INTO public.hosts (dhcp_identifier, dhcp_identifier_type, dhcp4_subnet_id, ipv4_address, dhcp4_client_classes, dhcp4_boot_file_name, dhcp4_next_server, user_context)
                VALUES (
                    v_new_mac_bytes, 
                    0, 
                    v_subnet_id_cm,
                    v_ip_cm_int,
                    'docsis_modems',
                    v_bootfile,
                    (v_server_ip_inet - '0.0.0.0'::inet),
                    jsonb_build_object(
                        'tipo', 'Cablemodem',
                        'servicio_id', NEW.id,
                        'cliente_id', NEW.id_cliente,
                        'cmts_id', NEW.id_cmts
                    )
                ) RETURNING host_id INTO v_host_id_cm;

                -- Inyectar el BOOTFILE (Opción 67) definitivo
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

                -- Registrar CPE del Cliente (Tipo 4) definitivo
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

                -- Actualizar el estado del equipo a ACTIVO
                UPDATE admin.equipos SET estado = 'ACTIVO' WHERE id = NEW.id_equipo;

                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            -- Desasociar y volver a asociar el Trigger para garantizar que esté fresco y activo
            DROP TRIGGER IF EXISTS trg_sync_servicio_to_kea_hosts ON admin.servicios_clientes;
            CREATE TRIGGER trg_sync_servicio_to_kea_hosts
            AFTER INSERT OR UPDATE OR DELETE ON admin.servicios_clientes
            FOR EACH ROW EXECUTE FUNCTION admin.sync_servicio_to_kea_hosts();
        ");
        string? detectedIp = null;
        try
        {
            using (var socket = new System.Net.Sockets.Socket(System.Net.Sockets.AddressFamily.InterNetwork, System.Net.Sockets.SocketType.Dgram, 0))
            {
                socket.Connect("8.8.8.8", 65530);
                if (socket.LocalEndPoint is System.Net.IPEndPoint endPoint)
                {
                    detectedIp = endPoint.Address.ToString();
                }
            }
        }
        catch
        {
            // Sin conexión a Internet o sin ruta por defecto en tabla de ruteo
        }

        if (string.IsNullOrEmpty(detectedIp))
        {
            try
            {
                foreach (var ni in System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.NetworkInterfaceType == System.Net.NetworkInformation.NetworkInterfaceType.Loopback || 
                        ni.OperationalStatus != System.Net.NetworkInformation.OperationalStatus.Up)
                        continue;

                    if (ni.Name.StartsWith("docker") || ni.Name.StartsWith("veth") || ni.Name.StartsWith("br-"))
                        continue;

                    foreach (var addr in ni.GetIPProperties().UnicastAddresses)
                    {
                        if (addr.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                        {
                            string ip = addr.Address.ToString();
                            if (!ip.StartsWith("127."))
                            {
                                detectedIp = ip;
                                break;
                            }
                        }
                    }
                    if (!string.IsNullOrEmpty(detectedIp)) break;
                }
            }
            catch {}
        }

        string infraServerIp = Environment.GetEnvironmentVariable("INFRA_SERVER_IP") 
            ?? detectedIp 
            ?? "192.168.2.106";

        Console.WriteLine($"[STARTUP] IP de Infraestructura Detectada Automáticamente: {infraServerIp}");
        cmd.CommandText = cmd.CommandText.Replace("'192.168.2.106'", $"'{infraServerIp}'");

        cmd.Parameters.AddWithValue("admin_hash", adminPasswordHash);
        await cmd.ExecuteNonQueryAsync();
        Console.WriteLine("[MIGRATION] Base de datos e Infraestructura de Seguridad migradas, sembradas y desbloqueadas con éxito.");

        // --- SDN: AUTOMATIC STARTUP KEA SYNCHRONIZATION ---
        try
        {
            Console.WriteLine("[STARTUP] Sincronizando configuración de Kea con la base de datos...");
            await SmiApi.Controllers.RedController.SyncKeaConfigAsync(dataSource);
            Console.WriteLine("[STARTUP] Configuración de Kea sincronizada con éxito.");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[STARTUP WARNING] No se pudo sincronizar Kea al iniciar: {ex.Message}");
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[MIGRATION WARNING] No se pudo ejecutar la migración automática: {ex.Message}");
    }
}

// =========================================================================
// 5. CONFIGURACIÓN DEL PIPELINE DE MIDDLEWARES (Request Lifecycle)
// =========================================================================

// Middleware Global de Excepciones (RFC 7807) en el tope del pipeline
app.UseMiddleware<ExceptionMiddleware>();

app.UseCors("AllowAll");

// Activar Swagger / OpenAPI (Generación con Swashbuckle y Visualización con Scalar)
app.UseSwagger();

app.MapScalarApiReference(options =>
{
    options
        .WithTitle("SPI ISP Provisioning API (.NET 8)")
        .WithTheme(ScalarTheme.Mars)
        .WithOpenApiRoutePattern("/swagger/{documentName}/swagger.json");
});

app.MapGet("/", async context =>
{
    context.Response.Redirect("/scalar/v1");
    await Task.CompletedTask;
});

// Autenticación (Debe ir antes de Autorización)
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();
