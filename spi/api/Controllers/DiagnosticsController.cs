using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize(Roles = "ADMIN")] // Estricta restricción de seguridad a nivel de rol de administrador
    public class DiagnosticsController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;

        public DiagnosticsController(NpgsqlDataSource dataSource)
        {
            _dataSource = dataSource;
        }

        // GET /api/diagnostics/leases
        [HttpGet("leases")]
        public async Task<IActionResult> GetLeases()
        {
            var list = new List<object>();
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT 
                        ('0.0.0.0'::inet + address)::text AS ip_address, 
                        encode(hwaddr, 'hex') AS mac_hex, 
                        valid_lifetime, 
                        expire, 
                        state 
                    FROM public.lease4 
                    ORDER BY expire DESC 
                    LIMIT 200;");

                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var ip = reader.IsDBNull(0) ? null : reader.GetString(0);
                    var macHex = reader.IsDBNull(1) ? null : reader.GetString(1);
                    var validLifetime = reader.GetInt64(2);
                    var expire = reader.IsDBNull(3) ? (DateTime?)null : reader.GetDateTime(3);
                    var state = reader.GetInt32(4);

                    list.Add(new
                    {
                        IpAddress = ip,
                        MacAddress = FormatMac(macHex),
                        ValidLifetime = validLifetime,
                        Expire = expire,
                        State = GetLeaseStateName(state),
                        StateId = state
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al leer leases de Kea: {ex.Message}" });
            }
        }

        // GET /api/diagnostics/hosts
        [HttpGet("hosts")]
        public async Task<IActionResult> GetHosts()
        {
            var list = new List<object>();
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT 
                        host_id AS id, 
                        encode(dhcp_identifier, 'hex') AS mac_hex, 
                        dhcp_identifier_type, 
                        ('0.0.0.0'::inet + ipv4_address)::text AS ip_address, 
                        hostname,
                        dhcp4_client_classes AS clase,
                        CASE 
                            WHEN user_context LIKE '{%}' THEN (user_context::jsonb)->>'tipo' 
                            ELSE NULL 
                        END AS tipo_dispositivo
                    FROM public.hosts 
                    ORDER BY host_id DESC 
                    LIMIT 200;");

                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var id = reader.GetInt32(0);
                    var macHex = reader.IsDBNull(1) ? null : reader.GetString(1);
                    var identifierType = reader.GetInt32(2);
                    var ip = reader.IsDBNull(3) ? null : reader.GetString(3);
                    var hostname = reader.IsDBNull(4) ? null : reader.GetString(4);
                    var clase = reader.IsDBNull(5) ? null : reader.GetString(5);
                    var tipoDispositivo = reader.IsDBNull(6) ? null : reader.GetString(6);

                    list.Add(new
                    {
                        Id = id,
                        MacAddress = FormatMac(macHex),
                        IdentifierType = identifierType,
                        IpAddress = ip,
                        Hostname = hostname,
                        Clase = clase,
                        TipoDispositivo = tipoDispositivo
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al leer host reservations de Kea: {ex.Message}" });
            }
        }

        private static string FormatMac(string? hex)
        {
            if (string.IsNullOrEmpty(hex)) return string.Empty;

            // Si es un flex-id con extensión de signo ffffff, lo limpiamos para mostrar la MAC original
            if (hex.Contains("ffffff", StringComparison.OrdinalIgnoreCase))
            {
                var cleanHex = new System.Text.StringBuilder();
                int i = 0;
                while (i < hex.Length)
                {
                    if (i + 8 <= hex.Length && hex.Substring(i, 6).Equals("ffffff", StringComparison.OrdinalIgnoreCase))
                    {
                        // Es un byte negativo con extensión ffffffXX, saltamos ffffff y tomamos XX
                        cleanHex.Append(hex.Substring(i + 6, 2));
                        i += 8;
                    }
                    else if (i + 2 <= hex.Length)
                    {
                        cleanHex.Append(hex.Substring(i, 2));
                        i += 2;
                    }
                    else
                    {
                        break;
                    }
                }
                hex = cleanHex.ToString();
            }

            if (hex.Length != 12) return hex;
            return $"{hex[0..2]}:{hex[2..4]}:{hex[4..6]}:{hex[6..8]}:{hex[8..10]}:{hex[10..12]}";
        }

        private static string GetLeaseStateName(int state)
        {
            return state switch
            {
                0 => "Activo (Default)",
                1 => "Rechazado (Declined)",
                2 => "Expirado-Recuperado (Expired-Reclaimed)",
                _ => $"Desconocido ({state})"
            };
        }

        // GET /api/diagnostics/history/ip?query=...
        [HttpGet("history/ip")]
        public async Task<IActionResult> GetIpHistory([FromQuery] string? query)
        {
            var list = new List<object>();
            try
            {
                var searchQuery = string.IsNullOrWhiteSpace(query) ? "" : $"%{query.Trim()}%";

                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT 
                        h.id, 
                        h.ip::text AS ip_address, 
                        h.mac::text AS mac_address, 
                        h.fecha_desde, 
                        h.fecha_hasta, 
                        c.razon_social AS cliente 
                    FROM admin.historial_leases_ip h
                    LEFT JOIN admin.clientes c ON c.id = h.id_cliente
                    WHERE 
                        $1 = '' OR (h.ip::text ILIKE $1 OR h.mac::text ILIKE $1 OR c.razon_social ILIKE $1)
                    ORDER BY h.fecha_desde DESC
                    LIMIT 100;");

                cmd.Parameters.AddWithValue(searchQuery);

                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var id = reader.GetInt64(0);
                    var ip = reader.IsDBNull(1) ? null : reader.GetString(1);
                    var macHex = reader.IsDBNull(2) ? null : reader.GetString(2);
                    var fechaDesde = reader.GetDateTime(3);
                    var fechaHasta = reader.IsDBNull(4) ? (DateTime?)null : reader.GetDateTime(4);
                    var cliente = reader.IsDBNull(5) ? "Desconocido (Dispositivo CPE Externo)" : reader.GetString(5);

                    list.Add(new
                    {
                        Id = id,
                        IpAddress = ip,
                        MacAddress = FormatMac(macHex?.Replace(":", "")),
                        FechaDesde = fechaDesde,
                        FechaHasta = fechaHasta,
                        Cliente = cliente
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al leer historial de IPs: {ex.Message}" });
            }
        }

        // GET /api/diagnostics/history/hardware?query=...
        [HttpGet("history/hardware")]
        public async Task<IActionResult> GetHardwareHistory([FromQuery] string? query)
        {
            var list = new List<object>();
            try
            {
                var searchQuery = string.IsNullOrWhiteSpace(query) ? "" : $"%{query.Trim()}%";

                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT 
                        h.id, 
                        e.mac::text AS mac_address, 
                        m.nombre AS modelo_equipo,
                        c.razon_social AS cliente, 
                        h.fecha_entrega, 
                        h.fecha_devolucion, 
                        h.motivo_cambio, 
                        u.nombre_completo AS operador
                    FROM admin.historial_equipos_clientes h
                    JOIN admin.equipos e ON e.id = h.id_equipo
                    JOIN admin.modelos m ON m.id = e.id_modelo
                    JOIN admin.clientes c ON c.id = h.id_cliente
                    LEFT JOIN admin.usuarios u ON u.id = h.operador_id
                    WHERE 
                        $1 = '' OR (e.mac::text ILIKE $1 OR c.razon_social ILIKE $1 OR h.motivo_cambio ILIKE $1 OR m.nombre ILIKE $1)
                    ORDER BY h.fecha_entrega DESC
                    LIMIT 100;");

                cmd.Parameters.AddWithValue(searchQuery);

                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var id = reader.GetInt32(0);
                    var macHex = reader.IsDBNull(1) ? null : reader.GetString(1);
                    var modelo = reader.IsDBNull(2) ? "Genérico" : reader.GetString(2);
                    var cliente = reader.IsDBNull(3) ? "Desconocido" : reader.GetString(3);
                    var fechaEntrega = reader.GetDateTime(4);
                    var fechaDevolucion = reader.IsDBNull(5) ? (DateTime?)null : reader.GetDateTime(5);
                    var motivoCambio = reader.GetString(6);
                    var operador = reader.IsDBNull(7) ? "Sistema (DHCP Sync)" : reader.GetString(7);

                    list.Add(new
                    {
                        Id = id,
                        MacAddress = FormatMac(macHex?.Replace(":", "")),
                        Modelo = modelo,
                        Cliente = cliente,
                        FechaEntrega = fechaEntrega,
                        FechaDevolucion = fechaDevolucion,
                        MotivoCambio = motivoCambio,
                        Operador = operador
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al leer historial de equipamiento: {ex.Message}" });
            }
        }
    }
}
