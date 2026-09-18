using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ModelosController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;

        public ModelosController(NpgsqlDataSource dataSource)
        {
            _dataSource = dataSource;
        }

        // =========================================================================
        // 1. ENDPOINTS PARA MARCAS (Brands)
        // =========================================================================

        public class MarcaCreateDto
        {
            public string Nombre { get; set; } = null!;
        }

        // A. Listar todas las Marcas (GET /api/modelos/marcas)
        [HttpGet("marcas")]
        public async Task<IActionResult> GetMarcas()
        {
            var list = new List<object>();
            try
            {
                await using var cmd = _dataSource.CreateCommand("SELECT id, nombre FROM admin.marcas ORDER BY nombre ASC;");
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new { Id = reader.GetInt32(0), Nombre = reader.GetString(1) });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al listar marcas: {ex.Message}" });
            }
        }

        // B. Crear nueva Marca (POST /api/modelos/marcas)
        [HttpPost("marcas")]
        public async Task<IActionResult> CreateMarca([FromBody] MarcaCreateDto dto)
        {
            dto.Nombre = dto.Nombre?.Trim() ?? "";
            if (string.IsNullOrWhiteSpace(dto.Nombre) || dto.Nombre.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new { Error = "El nombre de la marca es obligatorio y no puede ser genérico." });
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand("INSERT INTO admin.marcas (nombre) VALUES ($1) RETURNING id, nombre;");
                cmd.Parameters.AddWithValue(dto.Nombre);
                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return StatusCode(201, new { Id = reader.GetInt32(0), Nombre = reader.GetString(1), Message = "Marca registrada con éxito" });
                }
                return BadRequest(new { Error = "Error al guardar marca." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23505")
            {
                return Conflict(new { Error = $"La marca '{dto.Nombre}' ya existe en el sistema." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error en la transacción: {ex.Message}" });
            }
        }

        // C. Eliminar una Marca (DELETE /api/modelos/marcas/{id})
        [HttpDelete("marcas/{id}")]
        public async Task<IActionResult> DeleteMarca(int id)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand("DELETE FROM admin.marcas WHERE id = $1 RETURNING id;");
                cmd.Parameters.AddWithValue(id);
                var result = await cmd.ExecuteScalarAsync();
                if (result == null)
                {
                    return NotFound(new { Error = "La marca solicitada no existe." });
                }
                return Ok(new { Id = id, Message = "Marca eliminada con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503")
            {
                return BadRequest(new { Error = "No se puede eliminar la marca porque tiene modelos de equipos vinculados a ella." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar marca: {ex.Message}" });
            }
        }


        // =========================================================================
        // 2. ENDPOINTS PARA MODELOS (Hardware Models)
        // =========================================================================

        public class ModeloCreateDto
        {
            public int IdMarca { get; set; }
            public string Nombre { get; set; } = null!;
            public string Tipo { get; set; } = null!; // DOCSIS o GPON
            public string? Descripcion { get; set; }
        }

        // A. Listar todos los Modelos (GET /api/modelos)
        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var list = new List<object>();
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT m.id, m.nombre, m.tipo, m.descripcion, ma.id as id_marca, ma.nombre as marca 
                    FROM admin.modelos m
                    JOIN admin.marcas ma ON ma.id = m.id_marca
                    ORDER BY m.id DESC;");
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        Tipo = reader.GetString(2),
                        Descripcion = reader.IsDBNull(3) ? null : reader.GetString(3),
                        IdMarca = reader.GetInt32(4),
                        Marca = reader.GetString(5)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al listar modelos: {ex.Message}" });
            }
        }

        // B. Obtener un Modelo por ID (GET /api/modelos/{id})
        [HttpGet("{id}")]
        public async Task<IActionResult> GetById(int id)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT m.id, m.nombre, m.tipo, m.descripcion, ma.id as id_marca, ma.nombre as marca 
                    FROM admin.modelos m
                    JOIN admin.marcas ma ON ma.id = m.id_marca
                    WHERE m.id = $1;");
                cmd.Parameters.AddWithValue(id);
                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return Ok(new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        Tipo = reader.GetString(2),
                        Descripcion = reader.IsDBNull(3) ? null : reader.GetString(3),
                        IdMarca = reader.GetInt32(4),
                        Marca = reader.GetString(5)
                    });
                }
                return NotFound(new { Error = $"El modelo con ID {id} no fue encontrado." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al buscar modelo: {ex.Message}" });
            }
        }

        // C. Crear un nuevo Modelo (POST /api/modelos)
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] ModeloCreateDto dto)
        {
            dto.Nombre = dto.Nombre?.Trim() ?? "";
            dto.Tipo = dto.Tipo?.Trim().ToUpper() ?? "";
            dto.Descripcion = dto.Descripcion?.Trim();

            if (string.IsNullOrWhiteSpace(dto.Nombre) || dto.Nombre.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new { Error = "El nombre del modelo es obligatorio y no puede ser genérico." });
            }

            if (dto.Tipo != "DOCSIS" && dto.Tipo != "GPON")
            {
                return BadRequest(new { Error = "Tipo de modelo inválido. Debe ser obligatoriamente 'DOCSIS' o 'GPON'." });
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    INSERT INTO admin.modelos (id_marca, nombre, tipo, descripcion)
                    VALUES ($1, $2, $3, $4)
                    RETURNING id;");
                cmd.Parameters.AddWithValue(dto.IdMarca);
                cmd.Parameters.AddWithValue(dto.Nombre);
                cmd.Parameters.AddWithValue(dto.Tipo);
                cmd.Parameters.AddWithValue((object?)dto.Descripcion ?? DBNull.Value);

                var id = await cmd.ExecuteScalarAsync();
                return StatusCode(201, new { Id = id, Message = "Modelo de equipo registrado con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23505")
            {
                return Conflict(new { Error = "Ya existe un modelo registrado con ese nombre para esa marca." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503")
            {
                return BadRequest(new { Error = "La marca asociada al modelo no existe en la base de datos." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al registrar modelo: {ex.Message}" });
            }
        }

        // D. Modificar un Modelo Existente (PUT /api/modelos/{id})
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] ModeloCreateDto dto)
        {
            dto.Nombre = dto.Nombre?.Trim() ?? "";
            dto.Tipo = dto.Tipo?.Trim().ToUpper() ?? "";
            dto.Descripcion = dto.Descripcion?.Trim();

            if (string.IsNullOrWhiteSpace(dto.Nombre) || dto.Nombre.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new { Error = "El nombre del modelo no puede estar vacío ni ser genérico." });
            }

            if (dto.Tipo != "DOCSIS" && dto.Tipo != "GPON")
            {
                return BadRequest(new { Error = "El tipo de modelo debe ser 'DOCSIS' o 'GPON'." });
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.modelos 
                    SET id_marca = $1, nombre = $2, tipo = $3, descripcion = $4
                    WHERE id = $5
                    RETURNING id;");
                cmd.Parameters.AddWithValue(dto.IdMarca);
                cmd.Parameters.AddWithValue(dto.Nombre);
                cmd.Parameters.AddWithValue(dto.Tipo);
                cmd.Parameters.AddWithValue((object?)dto.Descripcion ?? DBNull.Value);
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null)
                {
                    return NotFound(new { Error = $"El modelo con ID {id} no fue encontrado para actualizar." });
                }

                return Ok(new { Id = id, Message = "Modelo de hardware actualizado con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23505")
            {
                return Conflict(new { Error = "Conflicto: Ya existe otro modelo con ese mismo nombre para esa marca." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al actualizar modelo: {ex.Message}" });
            }
        }

        // E. Eliminar un Modelo (DELETE /api/modelos/{id})
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand("DELETE FROM admin.modelos WHERE id = $1 RETURNING id;");
                cmd.Parameters.AddWithValue(id);
                var result = await cmd.ExecuteScalarAsync();
                if (result == null)
                {
                    return NotFound(new { Error = "El modelo solicitado no existe." });
                }
                return Ok(new { Id = id, Message = "Modelo de equipo eliminado con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503")
            {
                return BadRequest(new { Error = "No se puede eliminar el modelo porque existen equipos físicos en stock asignados a él." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar modelo: {ex.Message}" });
            }
        }
    }
}
