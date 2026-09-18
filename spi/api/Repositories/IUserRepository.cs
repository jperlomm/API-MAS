using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using SmiApi.Models;

namespace SmiApi.Repositories;

public interface IUserRepository
{
    Task<Usuario?> GetByUsernameAsync(string username);
    Task<Usuario?> GetByIdAsync(Guid id);
    Task<IEnumerable<Usuario>> GetAllAsync();
    Task<bool> CreateAsync(Usuario usuario);
    Task<bool> UpdateAsync(Usuario usuario);
    
    // Throttling de fuerza bruta
    Task IncrementFailedAttemptsAsync(string username, int attempts, DateTime? lockUntil);
    Task ResetFailedAttemptsAsync(Guid userId);
    
    // Refresh Tokens
    Task SaveRefreshTokenAsync(Guid userId, string tokenHash, DateTime expiresAt, string? ipAddress);
    Task<Guid?> ValidateAndRotateRefreshTokenAsync(string oldTokenHash, string newTokenHash, DateTime newExpiresAt, string? ipAddress);
    Task RevokeRefreshTokenAsync(string tokenHash);
    
    // Logs de Auditoría
    Task LogAuthenticationAsync(Guid? userId, string username, string ipAddress, string userAgent, bool success, string? details);
}
