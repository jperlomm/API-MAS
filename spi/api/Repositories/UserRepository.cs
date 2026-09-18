using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Npgsql;
using SmiApi.Models;

namespace SmiApi.Repositories;

public class UserRepository : IUserRepository
{
    private readonly NpgsqlDataSource _dataSource;

    public UserRepository(NpgsqlDataSource dataSource)
    {
        _dataSource = dataSource;
    }

    public async Task<Usuario?> GetByUsernameAsync(string username)
    {
        await using var cmd = _dataSource.CreateCommand(@"
            SELECT id, username, password_hash, nombre_completo, email, rol, activo, 
                   intentos_fallidos, bloqueado_hasta, fecha_creacion, fecha_modificacion 
            FROM admin.usuarios 
            WHERE username = @username");
        
        cmd.Parameters.AddWithValue("username", username);
        
        await using var reader = await cmd.ExecuteReaderAsync();
        if (await reader.ReadAsync())
        {
            return MapUsuarioFromReader(reader);
        }
        return null;
    }

    public async Task<Usuario?> GetByIdAsync(Guid id)
    {
        await using var cmd = _dataSource.CreateCommand(@"
            SELECT id, username, password_hash, nombre_completo, email, rol, activo, 
                   intentos_fallidos, bloqueado_hasta, fecha_creacion, fecha_modificacion 
            FROM admin.usuarios 
            WHERE id = @id");
        
        cmd.Parameters.AddWithValue("id", id);
        
        await using var reader = await cmd.ExecuteReaderAsync();
        if (await reader.ReadAsync())
        {
            return MapUsuarioFromReader(reader);
        }
        return null;
    }

    public async Task<IEnumerable<Usuario>> GetAllAsync()
    {
        var list = new List<Usuario>();
        await using var cmd = _dataSource.CreateCommand(@"
            SELECT id, username, password_hash, nombre_completo, email, rol, activo, 
                   intentos_fallidos, bloqueado_hasta, fecha_creacion, fecha_modificacion 
            FROM admin.usuarios 
            ORDER BY fecha_creacion DESC");
        
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            list.Add(MapUsuarioFromReader(reader));
        }
        return list;
    }

    public async Task<bool> CreateAsync(Usuario usuario)
    {
        usuario.Id = usuario.Id == Guid.Empty ? Guid.NewGuid() : usuario.Id;
        
        await using var cmd = _dataSource.CreateCommand(@"
            INSERT INTO admin.usuarios (id, username, password_hash, nombre_completo, email, rol, activo, intentos_fallidos, bloqueado_hasta)
            VALUES (@id, @username, @password_hash, @nombre_completo, @email, @rol, @activo, @intentos_fallidos, @bloqueado_hasta)");
        
        cmd.Parameters.AddWithValue("id", usuario.Id);
        cmd.Parameters.AddWithValue("username", usuario.Username);
        cmd.Parameters.AddWithValue("password_hash", usuario.PasswordHash);
        cmd.Parameters.AddWithValue("nombre_completo", usuario.NombreCompleto);
        cmd.Parameters.AddWithValue("email", usuario.Email);
        cmd.Parameters.AddWithValue("rol", usuario.Rol);
        cmd.Parameters.AddWithValue("activo", usuario.Activo);
        cmd.Parameters.AddWithValue("intentos_fallidos", usuario.IntentosFallidos);
        cmd.Parameters.AddWithValue("bloqueado_hasta", (object?)usuario.BloqueadoHasta ?? DBNull.Value);
        
        return await cmd.ExecuteNonQueryAsync() > 0;
    }

    public async Task<bool> UpdateAsync(Usuario usuario)
    {
        await using var cmd = _dataSource.CreateCommand(@"
            UPDATE admin.usuarios 
            SET username = @username, 
                password_hash = @password_hash, 
                nombre_completo = @nombre_completo, 
                email = @email, 
                rol = @rol, 
                activo = @activo, 
                intentos_fallidos = @intentos_fallidos, 
                bloqueado_hasta = @bloqueado_hasta,
                fecha_modificacion = NOW()
            WHERE id = @id");
        
        cmd.Parameters.AddWithValue("id", usuario.Id);
        cmd.Parameters.AddWithValue("username", usuario.Username);
        cmd.Parameters.AddWithValue("password_hash", usuario.PasswordHash);
        cmd.Parameters.AddWithValue("nombre_completo", usuario.NombreCompleto);
        cmd.Parameters.AddWithValue("email", usuario.Email);
        cmd.Parameters.AddWithValue("rol", usuario.Rol);
        cmd.Parameters.AddWithValue("activo", usuario.Activo);
        cmd.Parameters.AddWithValue("intentos_fallidos", usuario.IntentosFallidos);
        cmd.Parameters.AddWithValue("bloqueado_hasta", (object?)usuario.BloqueadoHasta ?? DBNull.Value);
        
        return await cmd.ExecuteNonQueryAsync() > 0;
    }

    public async Task IncrementFailedAttemptsAsync(string username, int attempts, DateTime? lockUntil)
    {
        await using var cmd = _dataSource.CreateCommand(@"
            UPDATE admin.usuarios 
            SET intentos_fallidos = @attempts, 
                bloqueado_hasta = @lock_until,
                fecha_modificacion = NOW()
            WHERE username = @username");
        
        cmd.Parameters.AddWithValue("username", username);
        cmd.Parameters.AddWithValue("attempts", attempts);
        cmd.Parameters.AddWithValue("lock_until", (object?)lockUntil ?? DBNull.Value);
        
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task ResetFailedAttemptsAsync(Guid userId)
    {
        await using var cmd = _dataSource.CreateCommand(@"
            UPDATE admin.usuarios 
            SET intentos_fallidos = 0, 
                bloqueado_hasta = NULL,
                fecha_modificacion = NOW()
            WHERE id = @id");
        
        cmd.Parameters.AddWithValue("id", userId);
        
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task SaveRefreshTokenAsync(Guid userId, string tokenHash, DateTime expiresAt, string? ipAddress)
    {
        await using var cmd = _dataSource.CreateCommand(@"
            INSERT INTO admin.user_refresh_tokens (usuario_id, token_hash, fecha_expiracion, creado_desde_ip, revocado)
            VALUES (@usuario_id, @token_hash, @fecha_expiracion, @creado_desde_ip, FALSE)");
        
        cmd.Parameters.AddWithValue("usuario_id", userId);
        cmd.Parameters.AddWithValue("token_hash", tokenHash);
        cmd.Parameters.AddWithValue("fecha_expiracion", expiresAt.ToUniversalTime());
        cmd.Parameters.AddWithValue("creado_desde_ip", (object?)ipAddress ?? DBNull.Value);
        
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task<Guid?> ValidateAndRotateRefreshTokenAsync(string oldTokenHash, string newTokenHash, DateTime newExpiresAt, string? ipAddress)
    {
        // 1. Validar el token viejo usando una transacción para garantizar consistencia y One-Time Use
        await using var connection = await _dataSource.OpenConnectionAsync();
        await using var transaction = await connection.BeginTransactionAsync();

        try
        {
            Guid? userId = null;

            // Buscar si existe el token activo y vigente
            await using (var cmdCheck = new NpgsqlCommand(@"
                SELECT usuario_id, revocado, fecha_expiracion 
                FROM admin.user_refresh_tokens 
                WHERE token_hash = @token_hash FOR UPDATE", connection, transaction))
            {
                cmdCheck.Parameters.AddWithValue("token_hash", oldTokenHash);
                await using var reader = await cmdCheck.ExecuteReaderAsync();
                
                if (await reader.ReadAsync())
                {
                    bool revocado = reader.GetBoolean(1);
                    DateTime fechaExpiracion = reader.GetDateTime(2);
                    
                    if (revocado)
                    {
                        // ATAQUE DETECTADO: El token ya había sido usado. Por políticas estrictas, revocamos TODOS
                        // los tokens activos de este usuario para cerrar todas sus sesiones activas de inmediato.
                        Guid victimId = reader.GetGuid(0);
                        await reader.CloseAsync(); // Cerrar reader antes de ejecutar updates
                        
                        await using (var cmdRevokeAll = new NpgsqlCommand(@"
                            UPDATE admin.user_refresh_tokens 
                            SET revocado = TRUE 
                            WHERE usuario_id = @usuario_id", connection, transaction))
                        {
                            cmdRevokeAll.Parameters.AddWithValue("usuario_id", victimId);
                            await cmdRevokeAll.ExecuteNonQueryAsync();
                        }
                        
                        await transaction.CommitAsync();
                        return null; // Retorna nulo, bloqueando el refresco
                    }

                    if (fechaExpiracion < DateTime.UtcNow)
                    {
                        await reader.CloseAsync();
                        // Expirado, no sirve más
                        await transaction.RollbackAsync();
                        return null;
                    }

                    userId = reader.GetGuid(0);
                }
                else
                {
                    await reader.CloseAsync();
                    await transaction.RollbackAsync();
                    return null;
                }
                
                await reader.CloseAsync();
            }

            if (userId.HasValue)
            {
                // 2. Revocar el token viejo
                await using (var cmdRevokeOld = new NpgsqlCommand(@"
                    UPDATE admin.user_refresh_tokens 
                    SET revocado = TRUE 
                    WHERE token_hash = @token_hash", connection, transaction))
                {
                    cmdRevokeOld.Parameters.AddWithValue("token_hash", oldTokenHash);
                    await cmdRevokeOld.ExecuteNonQueryAsync();
                }

                // 3. Registrar el token nuevo
                await using (var cmdInsertNew = new NpgsqlCommand(@"
                    INSERT INTO admin.user_refresh_tokens (usuario_id, token_hash, fecha_expiracion, creado_desde_ip, revocado)
                    VALUES (@usuario_id, @token_hash, @fecha_expiracion, @creado_desde_ip, FALSE)", connection, transaction))
                {
                    cmdInsertNew.Parameters.AddWithValue("usuario_id", userId.Value);
                    cmdInsertNew.Parameters.AddWithValue("token_hash", newTokenHash);
                    cmdInsertNew.Parameters.AddWithValue("fecha_expiracion", newExpiresAt.ToUniversalTime());
                    cmdInsertNew.Parameters.AddWithValue("creado_desde_ip", (object?)ipAddress ?? DBNull.Value);
                    await cmdInsertNew.ExecuteNonQueryAsync();
                }

                await transaction.CommitAsync();
                return userId.Value;
            }
            
            await transaction.RollbackAsync();
            return null;
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }

    public async Task RevokeRefreshTokenAsync(string tokenHash)
    {
        await using var cmd = _dataSource.CreateCommand(@"
            UPDATE admin.user_refresh_tokens 
            SET revocado = TRUE 
            WHERE token_hash = @token_hash");
        
        cmd.Parameters.AddWithValue("token_hash", tokenHash);
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task LogAuthenticationAsync(Guid? userId, string username, string ipAddress, string userAgent, bool success, string? details)
    {
        await using var cmd = _dataSource.CreateCommand(@"
            INSERT INTO admin.logs_autenticacion (usuario_id, username_ingresado, ip_origen, user_agent, exitoso, detalles)
            VALUES (@usuario_id, @username_ingresado, @ip_origen, @user_agent, @exitoso, @detalles)");
        
        cmd.Parameters.AddWithValue("usuario_id", (object?)userId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("username_ingresado", username);
        cmd.Parameters.AddWithValue("ip_origen", ipAddress);
        cmd.Parameters.AddWithValue("user_agent", userAgent);
        cmd.Parameters.AddWithValue("exitoso", success);
        cmd.Parameters.AddWithValue("detalles", (object?)details ?? DBNull.Value);
        
        await cmd.ExecuteNonQueryAsync();
    }

    private static Usuario MapUsuarioFromReader(NpgsqlDataReader reader)
    {
        return new Usuario
        {
            Id = reader.GetGuid(0),
            Username = reader.GetString(1),
            PasswordHash = reader.GetString(2),
            NombreCompleto = reader.GetString(3),
            Email = reader.GetString(4),
            Rol = reader.GetString(5),
            Activo = reader.GetBoolean(6),
            IntentosFallidos = reader.GetInt32(7),
            BloqueadoHasta = reader.IsDBNull(8) ? null : reader.GetDateTime(8),
            FechaCreacion = reader.GetDateTime(9),
            FechaModificacion = reader.GetDateTime(10)
        };
    }
}
