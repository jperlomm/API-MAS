using System;

namespace SmiApi.DTOs;

public class LoginRequest
{
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

public class AuthResponse
{
    public string AccessToken { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string NombreCompleto { get; set; } = string.Empty;
    public string Rol { get; set; } = string.Empty;
}

public class UserResponse
{
    public Guid Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string NombreCompleto { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Rol { get; set; } = string.Empty;
    public bool Activo { get; set; }
    public DateTime FechaCreacion { get; set; }
}

public class CreateUserRequest
{
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string NombreCompleto { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Rol { get; set; } = "OPERADOR";
}

public class UpdateUserRequest
{
    public string NombreCompleto { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Rol { get; set; } = "OPERADOR";
    public bool Activo { get; set; } = true;
    public string? Password { get; set; } // Opcional, solo si se desea cambiar
}
