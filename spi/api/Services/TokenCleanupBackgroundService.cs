using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Npgsql;

namespace SmiApi.Services;

public class TokenCleanupBackgroundService : BackgroundService
{
    private readonly NpgsqlDataSource _dataSource;
    private readonly ILogger<TokenCleanupBackgroundService> _logger;

    public TokenCleanupBackgroundService(NpgsqlDataSource dataSource, ILogger<TokenCleanupBackgroundService> logger)
    {
        _dataSource = dataSource;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("[SERVICE] Servicio de limpieza diaria de Refresh Tokens iniciado.");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                _logger.LogInformation("[SERVICE] Ejecutando purga programada de tokens expirados y revocados...");
                
                await using var cmd = _dataSource.CreateCommand(@"
                    DELETE FROM admin.user_refresh_tokens 
                    WHERE fecha_expiracion < NOW() OR revocado = TRUE");
                
                int deletedCount = await cmd.ExecuteNonQueryAsync(stoppingToken);
                
                _logger.LogInformation("[SERVICE] Purga completada con éxito. Tokens obsoletos eliminados: {Count}", deletedCount);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[SERVICE] Error crítico al ejecutar la purga de tokens de refresco.");
            }

            // Esperar 24 horas antes del siguiente ciclo de purga
            try
            {
                await Task.Delay(TimeSpan.FromHours(24), stoppingToken);
            }
            catch (TaskCanceledException)
            {
                // El servicio se está deteniendo de forma normal
                break;
            }
        }

        _logger.LogInformation("[SERVICE] Servicio de limpieza diaria de Refresh Tokens detenido.");
    }
}
