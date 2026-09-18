using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ProvinciasController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;

        public ProvinciasController(NpgsqlDataSource dataSource)
        {
            _dataSource = dataSource;
        }

        public class ProvinciaDto
        {
            public string Nombre { get; set; } = null!;
            public int IdPais { get; set; }
        }

        // 1. LISTAR PROVINCIAS (GET /api/provincias)
        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var list = new List<object>();
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT p.id, p.nombre, p.id_pais, pa.nombre AS pais_nombre 
                    FROM admin.provincias p
                    JOIN admin.paises pa ON p.id_pais = pa.id
                    ORDER BY p.nombre ASC;");
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        IdPais = reader.GetInt32(2),
                        Pais = reader.GetString(3)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al listar provincias: {ex.Message}" });
            }
        }

        // 2. CREAR PROVINCIA (POST /api/provincias)
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] ProvinciaDto dto)
        {
            dto.Nombre = dto.Nombre?.Trim() ?? "";
            if (string.IsNullOrWhiteSpace(dto.Nombre))
            {
                return BadRequest(new { Error = "El nombre de la provincia es obligatorio." });
            }
            if (dto.IdPais <= 0)
            {
                return BadRequest(new { Error = "Debe asociar un país válido." });
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    INSERT INTO admin.provincias (nombre, id_pais)
                    VALUES ($1, $2)
                    ON CONFLICT (nombre, id_pais) DO UPDATE SET nombre = EXCLUDED.nombre
                    RETURNING id, nombre, id_pais;");
                cmd.Parameters.AddWithValue(dto.Nombre);
                cmd.Parameters.AddWithValue(dto.IdPais);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return StatusCode(201, new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        IdPais = reader.GetInt32(2),
                        Message = "Provincia registrada con éxito."
                    });
                }
                return BadRequest(new { Error = "No se pudo registrar la provincia." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al registrar provincia: {ex.Message}" });
            }
        }

        // 3. EDITAR PROVINCIA (PUT /api/provincias/{id})
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] ProvinciaDto dto)
        {
            dto.Nombre = dto.Nombre?.Trim() ?? "";
            if (string.IsNullOrWhiteSpace(dto.Nombre))
            {
                return BadRequest(new { Error = "El nombre de la provincia es obligatorio." });
            }
            if (dto.IdPais <= 0)
            {
                return BadRequest(new { Error = "Debe asociar un país válido." });
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.provincias 
                    SET nombre = $1, id_pais = $2 
                    WHERE id = $3 
                    RETURNING id, nombre, id_pais;");
                cmd.Parameters.AddWithValue(dto.Nombre);
                cmd.Parameters.AddWithValue(dto.IdPais);
                cmd.Parameters.AddWithValue(id);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return Ok(new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        IdPais = reader.GetInt32(2),
                        Message = "Provincia actualizada con éxito."
                    });
                }
                return NotFound(new { Error = $"La provincia con ID {id} no existe." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al actualizar provincia: {ex.Message}" });
            }
        }

        // 4. ELIMINAR PROVINCIA (DELETE /api/provincias/{id})
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                string nombre = "";

                // 1. Obtener datos de la provincia para la validación
                await using (var cmdGet = _dataSource.CreateCommand("SELECT nombre FROM admin.provincias WHERE id = $1;"))
                {
                    cmdGet.Parameters.AddWithValue(id);
                    var res = await cmdGet.ExecuteScalarAsync();
                    if (res == null)
                    {
                        return NotFound(new { Error = $"La provincia con ID {id} no fue encontrada." });
                    }
                    nombre = res.ToString() ?? "";
                }

                // 2. Validar si tiene localidades asociadas en admin.localidades
                int localitiesCount = 0;
                await using (var cmdCheck = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.localidades WHERE id_provincia = $1;"))
                {
                    cmdCheck.Parameters.AddWithValue(id);
                    localitiesCount = (int)(await cmdCheck.ExecuteScalarAsync() ?? 0);
                }

                if (localitiesCount > 0)
                {
                    return BadRequest(new { Error = $"No se puede eliminar la provincia '{nombre}' porque tiene {localitiesCount} localidad(es) o ciudad(es) asociada(s). Por favor, elimine las localidades primero para evitar pérdidas accidentales en cascada." });
                }

                // 3. Proceder con la eliminación física
                await using (var cmdDel = _dataSource.CreateCommand("DELETE FROM admin.provincias WHERE id = $1;"))
                {
                    cmdDel.Parameters.AddWithValue(id);
                    await cmdDel.ExecuteNonQueryAsync();
                }

                return Ok(new { Id = id, Message = "Provincia eliminada con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503")
            {
                return BadRequest(new { Error = "No se puede eliminar la provincia porque posee localidades asociadas." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar la provincia: {ex.Message}" });
            }
        }
    }
}
