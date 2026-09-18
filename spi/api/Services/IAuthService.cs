using System;
using System.Threading.Tasks;
using SmiApi.DTOs;
using SmiApi.Models;

namespace SmiApi.Services;

public class AuthResult
{
    public bool Success { get; set; }
    public string? AccessToken { get; set; }
    public string? RefreshToken { get; set; }
    public string? ErrorMessage { get; set; }
    public Usuario? Usuario { get; set; }
}

public interface IAuthService
{
    Task<AuthResult> LoginAsync(LoginRequest request, string ipAddress, string userAgent);
    Task<AuthResult> RefreshSessionAsync(string oldRefreshToken, string ipAddress);
    Task RevokeSessionAsync(string refreshToken);
}
