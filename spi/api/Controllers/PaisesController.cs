using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class PaisesController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;

        public PaisesController(NpgsqlDataSource dataSource)
        {
            _dataSource = dataSource;
        }

        public class PaisDto
        {
            public string Nombre { get; set; } = null!;
        }

        // 1. LISTAR PAISES (GET /api/paises)
        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var list = new List<object>();
            try
            {
                await using var cmd = _dataSource.CreateCommand("SELECT id, nombre FROM admin.paises ORDER BY nombre ASC;");
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new { Id = reader.GetInt32(0), Nombre = reader.GetString(1) });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al listar países: {ex.Message}" });
            }
        }

        // 2. CREAR PAIS (POST /api/paises)
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] PaisDto dto)
        {
            dto.Nombre = dto.Nombre?.Trim() ?? "";
            if (string.IsNullOrWhiteSpace(dto.Nombre))
            {
                return BadRequest(new { Error = "El nombre del país es obligatorio." });
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    INSERT INTO admin.paises (nombre)
                    VALUES ($1)
                    ON CONFLICT (nombre) DO UPDATE SET nombre = EXCLUDED.nombre
                    RETURNING id, nombre;");
                cmd.Parameters.AddWithValue(dto.Nombre);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return StatusCode(201, new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        Message = "País registrado con éxito."
                    });
                }
                return BadRequest(new { Error = "No se pudo registrar el país." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al registrar país: {ex.Message}" });
            }
        }

        // 3. EDITAR PAIS (PUT /api/paises/{id})
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] PaisDto dto)
        {
            dto.Nombre = dto.Nombre?.Trim() ?? "";
            if (string.IsNullOrWhiteSpace(dto.Nombre))
            {
                return BadRequest(new { Error = "El nombre del país es obligatorio." });
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.paises 
                    SET nombre = $1 
                    WHERE id = $2 
                    RETURNING id, nombre;");
                cmd.Parameters.AddWithValue(dto.Nombre);
                cmd.Parameters.AddWithValue(id);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return Ok(new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        Message = "País actualizado con éxito."
                    });
                }
                return NotFound(new { Error = $"El país con ID {id} no existe." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al actualizar país: {ex.Message}" });
            }
        }

        // 4. ELIMINAR PAIS (DELETE /api/paises/{id})
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                string nombre = "";

                // 1. Obtener datos del país para validaciones
                await using (var cmdGet = _dataSource.CreateCommand("SELECT nombre FROM admin.paises WHERE id = $1;"))
                {
                    cmdGet.Parameters.AddWithValue(id);
                    var res = await cmdGet.ExecuteScalarAsync();
                    if (res == null)
                    {
                        return NotFound(new { Error = $"El país con ID {id} no fue encontrado." });
                    }
                    nombre = res.ToString() ?? "";
                }

                // 2. Validar si tiene provincias asociadas en admin.provincias
                int provincesCount = 0;
                await using (var cmdCheck = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.provincias WHERE id_pais = $1;"))
                {
                    cmdCheck.Parameters.AddWithValue(id);
                    provincesCount = (int)(await cmdCheck.ExecuteScalarAsync() ?? 0);
                }

                if (provincesCount > 0)
                {
                    return BadRequest(new { Error = $"No se puede eliminar el país '{nombre}' porque tiene {provincesCount} provincia(s) o estado(s) asociado(s). Por favor, elimine las provincias primero para evitar pérdidas accidentales en cascada." });
                }

                // 3. Proceder con la eliminación física
                await using (var cmdDel = _dataSource.CreateCommand("DELETE FROM admin.paises WHERE id = $1;"))
                {
                    cmdDel.Parameters.AddWithValue(id);
                    await cmdDel.ExecuteNonQueryAsync();
                }

                return Ok(new { Id = id, Message = "País eliminado con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503")
            {
                return BadRequest(new { Error = "No se puede eliminar el país porque posee provincias o estados asociados." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar el país: {ex.Message}" });
            }
        }
    }
}
