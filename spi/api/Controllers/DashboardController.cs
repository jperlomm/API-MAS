using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using SmiApi.Services;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize] // Requiere login
    public class DashboardController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;
        private readonly KeaStatsService _keaStatsService;

        public DashboardController(NpgsqlDataSource dataSource, KeaStatsService keaStatsService)
        {
            _dataSource = dataSource;
            _keaStatsService = keaStatsService;
        }

        // GET /api/dashboard/kpis
        [HttpGet("kpis")]
        public async Task<IActionResult> GetKpis()
        {
            try
            {
                int clientesTotal = 0;
                int equiposTotal = 0;
                int equiposStock = 0;
                int equiposActivos = 0;
                int serviciosActivos = 0;
                int serviciosSuspendidos = 0;

                // 1. Clientes totales
                await using (var cmd = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.clientes;"))
                {
                    clientesTotal = (int)(await cmd.ExecuteScalarAsync() ?? 0);
                }

                // 2. Equipos totales
                await using (var cmd = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.equipos;"))
                {
                    equiposTotal = (int)(await cmd.ExecuteScalarAsync() ?? 0);
                }

                // 3. Equipos en Stock (INVENTARIO)
                await using (var cmd = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.equipos WHERE estado = 'INVENTARIO';"))
                {
                    equiposStock = (int)(await cmd.ExecuteScalarAsync() ?? 0);
                }

                // 4. Equipos Activos (ACTIVO)
                await using (var cmd = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.equipos WHERE estado = 'ACTIVO';"))
                {
                    equiposActivos = (int)(await cmd.ExecuteScalarAsync() ?? 0);
                }

                // 5. Servicios Activos (ACTIVO)
                await using (var cmd = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.servicios_clientes WHERE estado = 'ACTIVO';"))
                {
                    serviciosActivos = (int)(await cmd.ExecuteScalarAsync() ?? 0);
                }

                // 6. Servicios Suspendidos (SUSPENDIDO)
                await using (var cmd = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.servicios_clientes WHERE estado = 'SUSPENDIDO';"))
                {
                    serviciosSuspendidos = (int)(await cmd.ExecuteScalarAsync() ?? 0);
                }

                // 7. Carga de DHCP: Map legacy dhcpLoad5Min to current live AckPerMin to completely bypass Postgres
                int dhcpLoad5Min = _keaStatsService.KeaAvailable && _keaStatsService.AckPerMin.HasValue
                    ? (int)Math.Round(_keaStatsService.AckPerMin.Value)
                    : 0;

                // 8. Build detailed real-time DHCP Monitor object
                object? dhcpMonitor = null;
                if (_keaStatsService.KeaAvailable)
                {
                    dhcpMonitor = new
                    {
                        KeaAvailable = true,
                        Rates = new
                        {
                            DiscoverPerMin = _keaStatsService.DiscoverPerMin,
                            RequestPerMin = _keaStatsService.RequestPerMin,
                            AckPerMin = _keaStatsService.AckPerMin,
                            NakPerMin = _keaStatsService.NakPerMin,
                            DropPerMin = _keaStatsService.DropPerMin
                        },
                        Raw = new
                        {
                            DiscoverTotal = _keaStatsService.CurrentSample?.Discover,
                            RequestTotal = _keaStatsService.CurrentSample?.Request,
                            AckTotal = _keaStatsService.CurrentSample?.Ack,
                            NakTotal = _keaStatsService.CurrentSample?.Nak,
                            DropTotal = _keaStatsService.CurrentSample?.Drop
                        },
                        AckRequestRatio = _keaStatsService.AckRequestRatio
                    };
                }
                else
                {
                    dhcpMonitor = new
                    {
                        KeaAvailable = false,
                        Rates = (object?)null,
                        Raw = (object?)null,
                        AckRequestRatio = (double?)null
                    };
                }

                return Ok(new
                {
                    ClientesTotal = clientesTotal,
                    EquiposTotal = equiposTotal,
                    EquiposStock = equiposStock,
                    EquiposActivos = equiposActivos,
                    ServiciosActivos = serviciosActivos,
                    ServiciosSuspendidos = serviciosSuspendidos,
                    DhcpLoad5Min = dhcpLoad5Min,
                    DhcpMonitor = dhcpMonitor
                });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al calcular KPIs del Dashboard: {ex.Message}" });
            }
        }

        // GET /api/dashboard/history
        [HttpGet("history")]
        public async Task<IActionResult> GetHistory()
        {
            try
            {
                var entries = new System.Collections.Generic.List<object>();

                await using (var cmd = _dataSource.CreateCommand(@"
                    SELECT fecha, discovers, requests, acks, naks, drops 
                    FROM admin.dhcp_hourly_stats 
                    ORDER BY fecha DESC 
                    LIMIT 24;
                "))
                {
                    await using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        while (await reader.ReadAsync())
                        {
                            entries.Add(new
                            {
                                Fecha = reader.GetDateTime(0),
                                Discovers = reader.GetInt64(1),
                                Requests = reader.GetInt64(2),
                                Acks = reader.GetInt64(3),
                                Naks = reader.GetInt64(4),
                                Drops = reader.GetInt64(5)
                            });
                        }
                    }
                }

                // Return ordered chronologically for the chart (oldest first)
                entries.Reverse();

                return Ok(entries);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al obtener histórico DHCP: {ex.Message}" });
            }
        }
    }
}
