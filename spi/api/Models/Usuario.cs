using System;

namespace SmiApi.Models;

public class Usuario
{
    public Guid Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string NombreCompleto { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Rol { get; set; } = "OPERADOR"; // "ADMIN", "OPERADOR", "TECNICO"
    public bool Activo { get; set; } = true;
    public int IntentosFallidos { get; set; }
    public DateTime? BloqueadoHasta { get; set; }
    public DateTime FechaCreacion { get; set; }
    public DateTime FechaModificacion { get; set; }
}
