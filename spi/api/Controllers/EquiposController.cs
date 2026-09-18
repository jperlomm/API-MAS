using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class EquiposController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;

        public EquiposController(NpgsqlDataSource dataSource)
        {
            _dataSource = dataSource;
        }

        public class EquipoCreateDto
        {
            public int IdModelo { get; set; }
            public string Mac { get; set; } = null!;
            public string? NumeroSerie { get; set; }
            public string? Estado { get; set; }
        }

        // 1. INGRESO DE EQUIPOS AL STOCK (POST /api/equipos)
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] EquipoCreateDto dto)
        {
            // Sanitizar y recortar
            dto.Mac = dto.Mac?.Trim() ?? "";
            dto.NumeroSerie = dto.NumeroSerie?.Trim();

            if (string.IsNullOrWhiteSpace(dto.Mac) || dto.Mac.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new { Error = "La dirección MAC física del equipo es obligatoria y no puede ser un valor genérico." });
            }

            // Regex para dirección MAC estándar (con guiones, dos puntos, o sin formato de 12 caracteres hexadecimales)
            var macRegex = new System.Text.RegularExpressions.Regex(@"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$");
            var macRegexPlain = new System.Text.RegularExpressions.Regex(@"^[0-9A-Fa-f]{12}$");
            if (!macRegex.IsMatch(dto.Mac) && !macRegexPlain.IsMatch(dto.Mac))
            {
                return BadRequest(new { Error = "La dirección MAC provista no tiene un formato válido. Ejemplos aceptados: 7c:b2:1b:a0:00:f6, 7C-B2-1B-A0-00-F6 o 7CB21BA000F6." });
            }

            if (!string.IsNullOrEmpty(dto.NumeroSerie) && dto.NumeroSerie.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                dto.NumeroSerie = null; // Limpiar si es un placeholder de Swagger
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    INSERT INTO admin.equipos (id_modelo, mac, numero_serie, estado)
                    VALUES ($1, $2::macaddr, $3, COALESCE($4, 'INVENTARIO'))
                    RETURNING id, mac::text, estado;");

                cmd.Parameters.AddWithValue(dto.IdModelo);
                cmd.Parameters.AddWithValue(dto.Mac);
                cmd.Parameters.AddWithValue((object?)dto.NumeroSerie ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.Estado ?? DBNull.Value);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return StatusCode(201, new
                    {
                        Id = reader.GetInt32(0),
                        Mac = reader.GetString(1),
                        Estado = reader.GetString(2),
                        Message = "Equipo registrado con éxito en el stock administrativo"
                    });
                }
                return BadRequest(new { Error = "Error inesperado al insertar equipo" });
            }
            catch (PostgresException ex) when (ex.SqlState == "23505") // Código de duplicado en Postgres
            {
                return Conflict(new { Error = "La dirección MAC o el Número de Serie ingresados ya existen en el inventario" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"La MAC ingresada no tiene un formato hexadecimal válido o el modelo no existe: {ex.Message}" });
            }
        }

        // 2. OBTENER STOCK DE EQUIPOS (GET /api/equipos)
        [HttpGet]
        public async Task<IActionResult> GetAll([FromQuery] bool? soloLibres, [FromQuery] string? estado)
        {
            var list = new List<object>();
            try
            {
                string sql = @"
                    SELECT e.id, m.nombre as modelo, m.tipo, e.mac::text, e.numero_serie, e.estado, e.fecha_alta 
                    FROM admin.equipos e
                    JOIN admin.modelos m ON m.id = e.id_modelo
                    WHERE 1=1";

                var parameters = new List<object>();
                int paramIndex = 1;

                if (soloLibres == true)
                {
                    sql += $" AND e.estado = ${paramIndex++}";
                    parameters.Add("INVENTARIO");
                }
                else if (!string.IsNullOrWhiteSpace(estado))
                {
                    sql += $" AND e.estado = ${paramIndex++}";
                    parameters.Add(estado.Trim().ToUpper());
                }

                sql += " ORDER BY e.id DESC;";

                await using var cmd = _dataSource.CreateCommand(sql);
                foreach (var param in parameters)
                {
                    cmd.Parameters.AddWithValue(param);
                }

                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new
                    {
                        Id = reader.GetInt32(0),
                        Modelo = reader.GetString(1),
                        TipoTecnologico = reader.GetString(2),
                        Mac = reader.GetString(3),
                        NumeroSerie = reader.IsDBNull(4) ? null : reader.GetString(4),
                        Estado = reader.GetString(5),
                        FechaAlta = reader.GetDateTime(6)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al obtener stock: {ex.Message}" });
            }
        }

        // 2.1. CONSULTA EQUIPO INDIVIDUAL POR ID (GET /api/equipos/{id})
        [HttpGet("{id:int}")]
        public async Task<IActionResult> GetById(int id)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT e.id, m.nombre as modelo, m.tipo, e.mac::text, e.numero_serie, e.estado, e.fecha_alta 
                    FROM admin.equipos e
                    JOIN admin.modelos m ON m.id = e.id_modelo
                    WHERE e.id = $1;");
                cmd.Parameters.AddWithValue(id);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return Ok(new
                    {
                        Id = reader.GetInt32(0),
                        Modelo = reader.GetString(1),
                        TipoTecnologico = reader.GetString(2),
                        Mac = reader.GetString(3),
                        NumeroSerie = reader.IsDBNull(4) ? null : reader.GetString(4),
                        Estado = reader.GetString(5),
                        FechaAlta = reader.GetDateTime(6)
                    });
                }
                return NotFound(new { Error = $"El equipo con ID {id} no existe en el inventario." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al obtener equipo por ID: {ex.Message}" });
            }
        }

        // 2.2. CONSULTA EQUIPO INDIVIDUAL POR MAC (GET /api/equipos/mac/{mac})
        [HttpGet("mac/{mac}")]
        public async Task<IActionResult> GetByMac(string mac)
        {
            try
            {
                mac = mac?.Trim() ?? "";
                // Normalizar MAC
                var cleanMac = mac.Replace(":", "").Replace("-", "").Replace(".", "").ToLower();
                if (cleanMac.Length == 12)
                {
                    mac = $"{cleanMac[0..2]}:{cleanMac[2..4]}:{cleanMac[4..6]}:{cleanMac[6..8]}:{cleanMac[8..10]}:{cleanMac[10..12]}";
                }
                else
                {
                    return BadRequest(new { Error = "Formato de dirección MAC inválido. Debe tener 12 caracteres hexadecimales." });
                }

                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT e.id, m.nombre as modelo, m.tipo, e.mac::text, e.numero_serie, e.estado, e.fecha_alta 
                    FROM admin.equipos e
                    JOIN admin.modelos m ON m.id = e.id_modelo
                    WHERE e.mac = $1::macaddr;");
                cmd.Parameters.AddWithValue(mac);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return Ok(new
                    {
                        Id = reader.GetInt32(0),
                        Modelo = reader.GetString(1),
                        TipoTecnologico = reader.GetString(2),
                        Mac = reader.GetString(3),
                        NumeroSerie = reader.IsDBNull(4) ? null : reader.GetString(4),
                        Estado = reader.GetString(5),
                        FechaAlta = reader.GetDateTime(6)
                    });
                }
                return NotFound(new { Error = $"El equipo con dirección MAC {mac} no existe en el inventario." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al obtener equipo por MAC: {ex.Message}" });
            }
        }

        // 3. ELIMINAR EQUIPO (DELETE /api/equipos/{id})
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand("DELETE FROM admin.equipos WHERE id = $1 RETURNING id;");
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null)
                {
                    return NotFound(new { Error = $"El equipo con ID {id} no fue encontrado en el stock." });
                }

                return Ok(new { Id = id, Message = "Equipo físico eliminado del inventario con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503") // Violación de llave foránea restrict (ej: asignado a servicio)
            {
                return BadRequest(new { Error = "No se puede eliminar el equipo porque se encuentra actualmente activo o asignado a un servicio de cliente." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar equipo del inventario: {ex.Message}" });
            }
        }

        // 4. ACTUALIZAR EQUIPO (PUT /api/equipos/{id})
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] EquipoCreateDto dto)
        {
            // Sanitizar y recortar
            dto.Mac = dto.Mac?.Trim() ?? "";
            dto.NumeroSerie = dto.NumeroSerie?.Trim();

            if (string.IsNullOrWhiteSpace(dto.Mac) || dto.Mac.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new { Error = "La dirección MAC física del equipo es obligatoria y no puede ser un valor genérico." });
            }

            var macRegex = new System.Text.RegularExpressions.Regex(@"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$");
            var macRegexPlain = new System.Text.RegularExpressions.Regex(@"^[0-9A-Fa-f]{12}$");
            if (!macRegex.IsMatch(dto.Mac) && !macRegexPlain.IsMatch(dto.Mac))
            {
                return BadRequest(new { Error = "La dirección MAC provista no tiene un formato válido. Ejemplos aceptados: 7c:b2:1b:a0:00:f6, 7C-B2-1B-A0-00-F6 o 7CB21BA000F6." });
            }

            if (!string.IsNullOrEmpty(dto.NumeroSerie) && dto.NumeroSerie.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                dto.NumeroSerie = null;
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.equipos 
                    SET id_modelo = $1, 
                        mac = $2::macaddr, 
                        numero_serie = $3,
                        estado = COALESCE($4, estado)
                    WHERE id = $5
                    RETURNING id;");

                cmd.Parameters.AddWithValue(dto.IdModelo);
                cmd.Parameters.AddWithValue(dto.Mac);
                cmd.Parameters.AddWithValue((object?)dto.NumeroSerie ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.Estado ?? DBNull.Value);
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null)
                {
                    return NotFound(new { Error = $"El equipo con ID {id} no fue encontrado en el stock." });
                }

                return Ok(new { Id = id, Message = "Datos de hardware actualizados con éxito en el stock." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23505")
            {
                return Conflict(new { Error = "La dirección MAC o el Número de Serie ingresados ya existen en el inventario" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al actualizar equipo: {ex.Message}" });
            }
        }
    }
}
