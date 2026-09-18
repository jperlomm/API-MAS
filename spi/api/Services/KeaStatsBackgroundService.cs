using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace SmiApi.Services;

public class KeaStatsBackgroundService : BackgroundService
{
    private readonly KeaStatsService _keaStatsService;
    private readonly ILogger<KeaStatsBackgroundService> _logger;

    public KeaStatsBackgroundService(KeaStatsService keaStatsService, ILogger<KeaStatsBackgroundService> logger)
    {
        _keaStatsService = keaStatsService;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("[KEA MONITOR] Servicio de recolección de estadísticas de Kea en segundo plano iniciado.");

        // Delay starting by 5 seconds to ensure Kea socket directory exists and container matches fully
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
        catch (TaskCanceledException)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                _logger.LogDebug("[KEA MONITOR] Ejecutando consulta de estadísticas DHCPv4 sobre socket local...");
                await _keaStatsService.PollStatsAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[KEA MONITOR] Error inesperado en el ciclo de recolección de estadísticas de Kea.");
            }

            // Wait exactly 30 seconds between successive poll cycles
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
            }
            catch (TaskCanceledException)
            {
                break;
            }
        }

        _logger.LogInformation("[KEA MONITOR] Servicio de recolección de estadísticas de Kea en segundo plano detenido.");
    }
}
