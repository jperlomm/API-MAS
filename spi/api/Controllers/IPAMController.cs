using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using System.Security.Claims;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize] // Requiere token Bearer JWT válido para identificar al operador
    public class IPAMController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;

        public IPAMController(NpgsqlDataSource dataSource)
        {
            _dataSource = dataSource;
        }

        // GET /api/ipam/next-free-ip?idCmts=1&tipo=CPE&idPaquete=2
        [HttpGet("next-free-ip")]
        public async Task<IActionResult> GetNextFreeIp([FromQuery] int idCmts, [FromQuery] string tipo, [FromQuery] int? idPaquete = null)
        {
            if (string.IsNullOrWhiteSpace(tipo) || (tipo != "CM" && tipo != "CPE"))
            {
                return BadRequest(new { Error = "El parámetro 'tipo' es requerido y debe ser 'CM' o 'CPE'." });
            }
 
            // A. Obtener el UUID del operador que realiza el pre-arrendamiento
            var claimId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(claimId) || !Guid.TryParse(claimId, out var operadorId))
            {
                return Unauthorized(new { Error = "No se pudo determinar la identidad del operador activo a partir del token de sesión." });
            }
 
            try
            {
                await using var connection = await _dataSource.OpenConnectionAsync();
 
                // B. Buscar la subred asignada a este CMTS que corresponda al tipo (CM o CPE)
                int subredId;
                await using (var cmdGetSubred = new NpgsqlCommand(@"
                    SELECT s.id FROM admin.subredes s
                    JOIN admin.pools p ON p.id_subred = s.id
                    WHERE s.id_cmts = $1 AND s.tipo = $2
                      AND (
                        (
                          $3::int IS NOT NULL 
                          AND p.client_class = (SELECT dhcp4_client_class FROM admin.paquetes WHERE id = $3)
                        )
                        OR
                        ($3::int IS NULL AND p.client_class IS NULL)
                      )
                    ORDER BY 
                        COALESCE(p.es_estatico, FALSE) DESC, 
                        s.id
                    LIMIT 1;", connection))
                {
                    cmdGetSubred.Parameters.AddWithValue(idCmts);
                    cmdGetSubred.Parameters.AddWithValue(tipo);
                    cmdGetSubred.Parameters.AddWithValue((object)idPaquete ?? DBNull.Value);
 
                    var res = await cmdGetSubred.ExecuteScalarAsync();
                    if (res == null)
                    {
                        return NotFound(new { Error = $"No se encontró ninguna subred de tipo '{tipo}' activa en el CMTS con ID {idCmts}." });
                    }
                    subredId = Convert.ToInt32(res);
                }
 
                // C. Invocar la función PL/pgSQL que realiza la detección de huecos y el bloqueo de 5 minutos
                await using (var cmdGetIp = new NpgsqlCommand("SELECT admin.get_next_free_ip($1, $2, $3);", connection))
                {
                    cmdGetIp.Parameters.AddWithValue(subredId);
                    cmdGetIp.Parameters.AddWithValue(operadorId);
                    cmdGetIp.Parameters.AddWithValue((object)idPaquete ?? DBNull.Value);
 
                    var ipResult = await cmdGetIp.ExecuteScalarAsync();
                    if (ipResult == null || ipResult == DBNull.Value)
                    {
                        return BadRequest(new { Error = $"No hay direcciones IP estáticas libres disponibles en los pools reservados para subredes '{tipo}' de este CMTS." });
                    }
 
                    var ipString = ipResult.ToString();
                    return Ok(new { Ip = ipString });
                }
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Error = $"Error en el motor IPAM: {ex.Message}" });
            }
        }
    }
}
