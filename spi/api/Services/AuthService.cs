using System;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using SmiApi.DTOs;
using SmiApi.Models;
using SmiApi.Repositories;

namespace SmiApi.Services;

public class AuthService : IAuthService
{
    private readonly IUserRepository _userRepository;
    private readonly IConfiguration _configuration;

    public AuthService(IUserRepository userRepository, IConfiguration configuration)
    {
        _userRepository = userRepository;
        _configuration = configuration;
    }

    public async Task<AuthResult> LoginAsync(LoginRequest request, string ipAddress, string userAgent)
    {
        // 1. Obtener el usuario de la DB
        var usuario = await _userRepository.GetByUsernameAsync(request.Username);
        
        if (usuario == null)
        {
            // Registrar intento fallido para auditoría (usuario inexistente)
            await _userRepository.LogAuthenticationAsync(null, request.Username, ipAddress, userAgent, false, "Usuario inexistente");
            return new AuthResult { Success = false, ErrorMessage = "Credenciales incorrectas" };
        }

        // 2. Verificar si la cuenta está activa
        if (!usuario.Activo)
        {
            await _userRepository.LogAuthenticationAsync(usuario.Id, request.Username, ipAddress, userAgent, false, "Cuenta inactiva / suspendida");
            return new AuthResult { Success = false, ErrorMessage = "La cuenta se encuentra inactiva. Contacte al administrador." };
        }

        // 3. Verificar si la cuenta está bloqueada temporalmente por fuerza bruta
        if (usuario.BloqueadoHasta.HasValue && usuario.BloqueadoHasta.Value > DateTime.UtcNow)
        {
            var minutosRestantes = Math.Ceiling((usuario.BloqueadoHasta.Value - DateTime.UtcNow).TotalMinutes);
            await _userRepository.LogAuthenticationAsync(usuario.Id, request.Username, ipAddress, userAgent, false, $"Cuenta bloqueada por fuerza bruta. Minutos restantes: {minutosRestantes}");
            return new AuthResult 
            { 
                Success = false, 
                ErrorMessage = $"Cuenta bloqueada temporalmente por seguridad debido a demasiados intentos fallidos. Intente nuevamente en {minutosRestantes} minutos." 
            };
        }

        // 4. Verificar la contraseña usando BCrypt
        bool passwordValido = BCrypt.Net.BCrypt.Verify(request.Password, usuario.PasswordHash);

        if (!passwordValido)
        {
            // Incrementar contador de intentos fallidos
            int nuevosIntentos = usuario.IntentosFallidos + 1;
            DateTime? lockUntil = null;
            string detalles = $"Contraseña incorrecta. Intento fallido {nuevosIntentos}/5";

            if (nuevosIntentos >= 5)
            {
                lockUntil = DateTime.UtcNow.AddMinutes(15);
                detalles = "Cuenta bloqueada temporalmente por alcanzar 5 intentos fallidos.";
            }

            await _userRepository.IncrementFailedAttemptsAsync(usuario.Username, nuevosIntentos, lockUntil);
            await _userRepository.LogAuthenticationAsync(usuario.Id, request.Username, ipAddress, userAgent, false, detalles);

            return new AuthResult 
            { 
                Success = false, 
                ErrorMessage = nuevosIntentos >= 5 
                    ? "Demasiados intentos fallidos. Cuenta bloqueada por 15 minutos." 
                    : $"Credenciales incorrectas. Intentos restantes antes del bloqueo: {5 - nuevosIntentos}." 
            };
        }

        // 5. Autenticación exitosa -> Resetear intentos fallidos
        if (usuario.IntentosFallidos > 0)
        {
            await _userRepository.ResetFailedAttemptsAsync(usuario.Id);
        }

        // 6. Generar Tokens (Access Token JWT y Refresh Token)
        var accessToken = GenerateJwtToken(usuario);
        var rawRefreshToken = GenerateSecureRandomString();
        var hashedRefreshToken = HashToken(rawRefreshToken);

        // Guardar el Refresh Token en la DB (validez de 7 días)
        var refreshExpires = DateTime.UtcNow.AddDays(7);
        await _userRepository.SaveRefreshTokenAsync(usuario.Id, hashedRefreshToken, refreshExpires, ipAddress);

        // Auditar el inicio de sesión exitoso
        await _userRepository.LogAuthenticationAsync(usuario.Id, request.Username, ipAddress, userAgent, true, "Inicio de sesión exitoso");

        return new AuthResult
        {
            Success = true,
            AccessToken = accessToken,
            RefreshToken = rawRefreshToken,
            Usuario = usuario
        };
    }

    public async Task<AuthResult> RefreshSessionAsync(string oldRefreshToken, string ipAddress)
    {
        var hashedOldToken = HashToken(oldRefreshToken);
        
        // Preparar nuevos tokens de reemplazo
        var rawNewRefreshToken = GenerateSecureRandomString();
        var hashedNewRefreshToken = HashToken(rawNewRefreshToken);
        var newExpires = DateTime.UtcNow.AddDays(7);

        // Validar y rotar el Refresh Token de un solo uso en la base de datos de forma transaccional
        var userId = await _userRepository.ValidateAndRotateRefreshTokenAsync(
            hashedOldToken, 
            hashedNewRefreshToken, 
            newExpires, 
            ipAddress
        );

        if (!userId.HasValue)
        {
            return new AuthResult { Success = false, ErrorMessage = "Token de refresco inválido, vencido o revocado por anomalía." };
        }

        // Obtener el usuario para regenerar el JWT
        var usuario = await _userRepository.GetByIdAsync(userId.Value);
        if (usuario == null || !usuario.Activo)
        {
            return new AuthResult { Success = false, ErrorMessage = "Usuario inactivo o inexistente." };
        }

        var newAccessToken = GenerateJwtToken(usuario);

        return new AuthResult
        {
            Success = true,
            AccessToken = newAccessToken,
            RefreshToken = rawNewRefreshToken,
            Usuario = usuario
        };
    }

    public async Task RevokeSessionAsync(string refreshToken)
    {
        var hashedToken = HashToken(refreshToken);
        await _userRepository.RevokeRefreshTokenAsync(hashedToken);
    }

    // =========================================================================
    // Métodos Auxiliares Criptográficos
    // =========================================================================

    private string GenerateJwtToken(Usuario usuario)
    {
        var jwtSettings = _configuration.GetSection("Jwt");
        var secret = jwtSettings["Secret"] ?? "SPI_Super_Secret_Core_Carrier_Class_Signature_Key_2026!";
        var issuer = jwtSettings["Issuer"] ?? "spi-network.net";
        var audience = jwtSettings["Audience"] ?? "spi-network.net";

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, usuario.Id.ToString()),
            new Claim(ClaimTypes.Name, usuario.Username),
            new Claim(ClaimTypes.GivenName, usuario.NombreCompleto),
            new Claim(ClaimTypes.Email, usuario.Email),
            new Claim(ClaimTypes.Role, usuario.Rol)
        };

        var token = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(15), // Expiración corta de seguridad
            signingCredentials: creds
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static string GenerateSecureRandomString()
    {
        var randomBytes = new byte[64];
        using (var rng = RandomNumberGenerator.Create())
        {
            rng.GetBytes(randomBytes);
        }
        return Convert.ToBase64String(randomBytes)
            .Replace("+", "")
            .Replace("/", "")
            .Replace("=", ""); // Limpiar caracteres especiales de URL
    }

    private static string HashToken(string token)
    {
        var hashBytes = SHA256.HashData(Encoding.UTF8.GetBytes(token));
        return Convert.ToHexString(hashBytes).ToLower();
    }
}
