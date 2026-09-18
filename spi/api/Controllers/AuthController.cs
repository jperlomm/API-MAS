using System;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using FluentValidation;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmiApi.DTOs;
using SmiApi.Services;

namespace SmiApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly IAuthService _authService;
    private readonly IValidator<LoginRequest> _loginValidator;

    public AuthController(IAuthService authService, IValidator<LoginRequest> loginValidator)
    {
        _authService = authService;
        _loginValidator = loginValidator;
    }

    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        // 1. Validar el payload de entrada con FluentValidation
        var validationResult = await _loginValidator.ValidateAsync(request);
        if (!validationResult.IsValid)
        {
            return BadRequest(new
            {
                Type = "https://spi-network.net/errors/validation-error",
                Title = "Error de Validación de Campos",
                Status = StatusCodes.Status400BadRequest,
                Detail = "Algunos campos de la solicitud no son válidos.",
                Errors = validationResult.Errors.Select(e => e.ErrorMessage).ToList(),
                Instance = Request.Path.Value
            });
        }

        // 2. Extraer metadatos de red para auditoría
        var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "Desconocida";
        var userAgent = Request.Headers["User-Agent"].ToString() ?? "Desconocido";

        // 3. Autenticar
        var result = await _authService.LoginAsync(request, ipAddress, userAgent);

        if (!result.Success)
        {
            return BadRequest(new
            {
                Type = "https://spi-network.net/errors/invalid-credentials",
                Title = "Credenciales de Acceso Inválidas",
                Status = StatusCodes.Status400BadRequest,
                Detail = result.ErrorMessage,
                Instance = Request.Path.Value
            });
        }

        // 4. Adjuntar Refresh Token en cookie HttpOnly / Secure / SameSite=Strict
        AppendRefreshTokenCookie(result.RefreshToken!);

        // 5. Retornar Access Token en JSON
        return Ok(new AuthResponse
        {
            AccessToken = result.AccessToken!,
            Username = result.Usuario!.Username,
            NombreCompleto = result.Usuario.NombreCompleto,
            Rol = result.Usuario.Rol
        });
    }

    [HttpPost("refresh")]
    [AllowAnonymous]
    public async Task<IActionResult> Refresh()
    {
        // 1. Intentar extraer el Refresh Token de las cookies seguras
        if (!Request.Cookies.TryGetValue("refreshToken", out var refreshToken) || string.IsNullOrEmpty(refreshToken))
        {
            return Unauthorized(new
            {
                Type = "https://spi-network.net/errors/unauthorized",
                Title = "No Autorizado",
                Status = StatusCodes.Status401Unauthorized,
                Detail = "No se encontró el token de refresco en la solicitud. Inicie sesión nuevamente.",
                Instance = Request.Path.Value
            });
        }

        var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "Desconocida";

        // 2. Ejecutar la rotación transaccional de tokens en el servicio
        var result = await _authService.RefreshSessionAsync(refreshToken, ipAddress);

        if (!result.Success)
        {
            // Limpiar cookie corrupta/expirada
            Response.Cookies.Delete("refreshToken");
            return Unauthorized(new
            {
                Type = "https://spi-network.net/errors/refresh-failed",
                Title = "Refresco de Sesión Fallido",
                Status = StatusCodes.Status401Unauthorized,
                Detail = result.ErrorMessage,
                Instance = Request.Path.Value
            });
        }

        // 3. Escribir la nueva cookie de refresco rotada
        AppendRefreshTokenCookie(result.RefreshToken!);

        // 4. Responder con el nuevo Access Token
        return Ok(new AuthResponse
        {
            AccessToken = result.AccessToken!,
            Username = result.Usuario!.Username,
            NombreCompleto = result.Usuario.NombreCompleto,
            Rol = result.Usuario.Rol
        });
    }

    [HttpPost("logout")]
    [Authorize]
    public async Task<IActionResult> Logout()
    {
        if (Request.Cookies.TryGetValue("refreshToken", out var refreshToken))
        {
            await _authService.RevokeSessionAsync(refreshToken);
        }

        // Eliminar físicamente la cookie en el cliente
        Response.Cookies.Delete("refreshToken");
        return NoContent();
    }

    [HttpGet("profile")]
    [Authorize]
    public IActionResult GetProfile()
    {
        var idClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        var usernameClaim = User.FindFirst(ClaimTypes.Name)?.Value;
        var nombreClaim = User.FindFirst(ClaimTypes.GivenName)?.Value;
        var emailClaim = User.FindFirst(ClaimTypes.Email)?.Value;
        var rolClaim = User.FindFirst(ClaimTypes.Role)?.Value;

        return Ok(new
        {
            Id = idClaim,
            Username = usernameClaim,
            NombreCompleto = nombreClaim,
            Email = emailClaim,
            Rol = rolClaim
        });
    }

    private void AppendRefreshTokenCookie(string token)
    {
        var cookieOptions = new CookieOptions
        {
            HttpOnly = true,
            Secure = true, // Debe viajar solo por HTTPS en prod
            SameSite = SameSiteMode.Strict, // Antihack CSRF
            Expires = DateTimeOffset.UtcNow.AddDays(7)
        };
        Response.Cookies.Append("refreshToken", token, cookieOptions);
    }
}
