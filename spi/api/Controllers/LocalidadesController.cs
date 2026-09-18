using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class LocalidadesController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;

        public LocalidadesController(NpgsqlDataSource dataSource)
        {
            _dataSource = dataSource;
        }

        public class LocalidadDto
        {
            public string Nombre { get; set; } = null!;
            public int IdProvincia { get; set; }
        }

        // 1. OBTENER LOCALIDADES (GET /api/localidades)
        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var list = new List<object>();
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT l.id, l.nombre, l.id_provincia, pr.nombre AS provincia_nombre, pr.id_pais, pa.nombre AS pais_nombre
                    FROM admin.localidades l
                    JOIN admin.provincias pr ON l.id_provincia = pr.id
                    JOIN admin.paises pa ON pr.id_pais = pa.id
                    ORDER BY l.nombre ASC;");
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        IdProvincia = reader.GetInt32(2),
                        Provincia = reader.GetString(3),
                        IdPais = reader.GetInt32(4),
                        Pais = reader.GetString(5)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al listar localidades: {ex.Message}" });
            }
        }

        // 2. CREAR LOCALIDAD (POST /api/localidades)
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] LocalidadDto dto)
        {
            dto.Nombre = dto.Nombre?.Trim() ?? "";
            if (string.IsNullOrWhiteSpace(dto.Nombre))
            {
                return BadRequest(new { Error = "El nombre de la localidad es obligatorio." });
            }
            if (dto.IdProvincia <= 0)
            {
                return BadRequest(new { Error = "Debe asociar una provincia o estado válido." });
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    INSERT INTO admin.localidades (nombre, id_provincia)
                    VALUES ($1, $2)
                    ON CONFLICT (nombre, id_provincia) DO UPDATE SET nombre = EXCLUDED.nombre
                    RETURNING id, nombre, id_provincia;");
                cmd.Parameters.AddWithValue(dto.Nombre);
                cmd.Parameters.AddWithValue(dto.IdProvincia);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return StatusCode(201, new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        IdProvincia = reader.GetInt32(2),
                        Message = "Localidad registrada con éxito."
                    });
                }
                return BadRequest(new { Error = "No se pudo registrar la localidad." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al registrar localidad: {ex.Message}" });
            }
        }

        // 3. EDITAR LOCALIDAD (PUT /api/localidades/{id})
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] LocalidadDto dto)
        {
            dto.Nombre = dto.Nombre?.Trim() ?? "";
            if (string.IsNullOrWhiteSpace(dto.Nombre))
            {
                return BadRequest(new { Error = "El nombre de la localidad es obligatorio." });
            }
            if (dto.IdProvincia <= 0)
            {
                return BadRequest(new { Error = "Debe asociar una provincia o estado válido." });
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.localidades 
                    SET nombre = $1, id_provincia = $2 
                    WHERE id = $3 
                    RETURNING id, nombre, id_provincia;");
                cmd.Parameters.AddWithValue(dto.Nombre);
                cmd.Parameters.AddWithValue(dto.IdProvincia);
                cmd.Parameters.AddWithValue(id);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return Ok(new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        IdProvincia = reader.GetInt32(2),
                        Message = "Localidad actualizada con éxito."
                    });
                }
                return NotFound(new { Error = $"La localidad con ID {id} no existe." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al actualizar localidad: {ex.Message}" });
            }
        }

        // 4. ELIMINAR LOCALIDAD (DELETE /api/localidades/{id})
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                string nombre = "";

                // 1. Obtener datos de la localidad para la validación
                await using (var cmdGet = _dataSource.CreateCommand("SELECT nombre FROM admin.localidades WHERE id = $1;"))
                {
                    cmdGet.Parameters.AddWithValue(id);
                    var res = await cmdGet.ExecuteScalarAsync();
                    if (res == null)
                    {
                        return NotFound(new { Error = $"La localidad con ID {id} no fue encontrada." });
                    }
                    nombre = res.ToString() ?? "";
                }

                // 2. Validar si tiene clientes asociados en admin.clientes
                int clientsCount = 0;
                await using (var cmdCheck = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.clientes WHERE id_localidad = $1;"))
                {
                    cmdCheck.Parameters.AddWithValue(id);
                    clientsCount = (int)(await cmdCheck.ExecuteScalarAsync() ?? 0);
                }

                if (clientsCount > 0)
                {
                    return BadRequest(new { Error = $"No se puede eliminar la localidad '{nombre}' porque tiene {clientsCount} cliente(s) o abonado(s) comercial(es) asociado(s) a ella. Por favor, reasigne a estos abonados otra localidad antes de proceder." });
                }

                // 3. Proceder con la eliminación física
                await using (var cmdDel = _dataSource.CreateCommand("DELETE FROM admin.localidades WHERE id = $1;"))
                {
                    cmdDel.Parameters.AddWithValue(id);
                    await cmdDel.ExecuteNonQueryAsync();
                }

                return Ok(new { Id = id, Message = "Localidad eliminada con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503")
            {
                return BadRequest(new { Error = "No se puede eliminar la localidad porque posee recursos asociados." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar la localidad: {ex.Message}" });
            }
        }
    }
}
