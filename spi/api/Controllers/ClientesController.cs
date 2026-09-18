using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ClientesController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;

        public ClientesController(NpgsqlDataSource dataSource)
        {
            _dataSource = dataSource;
        }

        public class ClienteCreateDto
        {
            public string RazonSocial { get; set; } = null!;
            public string CuitDni { get; set; } = null!;
            public string? Telefono { get; set; }
            public string? Email { get; set; }
            public string? Calle { get; set; }
            public string? Altura { get; set; }
            public int? IdLocalidad { get; set; }
            public string? Pais { get; set; }
            public string? Codigo { get; set; }
            public string? Direccion { get; set; }
            public decimal? Latitud { get; set; }
            public decimal? Longitud { get; set; }
        }

        // 1. ALTA DE CLIENTES (POST /api/clientes)
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] ClienteCreateDto dto)
        {
            // Sanitizar y recortar espacios en blanco
            dto.RazonSocial = dto.RazonSocial?.Trim() ?? "";
            dto.CuitDni = dto.CuitDni?.Trim().Replace(".", "") ?? ""; // Eliminar puntos de formato en CUIT/DNI
            dto.Telefono = dto.Telefono?.Trim();
            dto.Email = dto.Email?.Trim();
            dto.Calle = dto.Calle?.Trim();
            dto.Altura = dto.Altura?.Trim();
            dto.Pais = string.IsNullOrWhiteSpace(dto.Pais) ? "Argentina" : dto.Pais.Trim();
            dto.Codigo = dto.Codigo?.Trim();
            dto.Direccion = dto.Direccion?.Trim();

            // 1. Validaciones para Razón Social
            if (string.IsNullOrWhiteSpace(dto.RazonSocial) || dto.RazonSocial.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new { Error = "La Razón Social / Nombre Completo es obligatorio y no puede ser genérico." });
            }
            if (dto.RazonSocial.Length < 3 || dto.RazonSocial.Length > 150)
            {
                return BadRequest(new { Error = "La Razón Social / Nombre Completo debe tener entre 3 y 150 caracteres." });
            }

            // 2. Validaciones para CUIT / DNI
            if (string.IsNullOrWhiteSpace(dto.CuitDni) || dto.CuitDni.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new { Error = "El CUIT o DNI es obligatorio y no puede ser genérico." });
            }
            
            // Regex para: DNI (7-8 dígitos), CUIT sin guiones (11 dígitos), o CUIT con guiones (XX-XXXXXXXX-X)
            var cuitDniRegex = new System.Text.RegularExpressions.Regex(@"^(\d{7,8}|\d{11}|\d{2}-\d{8}-\d{1})$");
            if (!cuitDniRegex.IsMatch(dto.CuitDni))
            {
                return BadRequest(new { Error = "Formato de CUIT/DNI no válido. Debe ingresar un DNI (7 u 8 números) o un CUIT (11 números sin guiones, o con guiones en formato XX-XXXXXXXX-X)." });
            }

            // 3. Validaciones de Email (opcional, pero con formato si se provee)
            if (!string.IsNullOrEmpty(dto.Email))
            {
                var emailRegex = new System.Text.RegularExpressions.Regex(@"^[^\s@]+@[^\s@]+\.[^\s@]+$");
                if (!emailRegex.IsMatch(dto.Email))
                {
                    return BadRequest(new { Error = "El Correo Electrónico provisto no tiene un formato válido." });
                }
            }

            // 4. Validaciones de Teléfono (opcional, pero con caracteres de marcado si se provee)
            if (!string.IsNullOrEmpty(dto.Telefono))
            {
                var phoneRegex = new System.Text.RegularExpressions.Regex(@"^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s\./0-9]{5,20}$");
                if (!phoneRegex.IsMatch(dto.Telefono))
                {
                    return BadRequest(new { Error = "El Teléfono provisto contiene caracteres no permitidos o tiene una longitud incorrecta (debe tener entre 5 y 20 caracteres numéricos/separadores)." });
                }
            }

            // 5. Validación de Código de Abonado/Facturación (Obligatorio)
            if (string.IsNullOrWhiteSpace(dto.Codigo))
            {
                return BadRequest(new { Error = "El Código de Abonado / Facturación es obligatorio para la compatibilidad con el sistema de cobros." });
            }

            try
            {
                // Calcular direccion completa compilada para mantener compatibilidad
                string? computedDireccion = null;
                if (!string.IsNullOrEmpty(dto.Calle))
                {
                    string localidadNombre = "";
                    string provinciaNombre = "";
                    string paisNombre = "";

                    if (dto.IdLocalidad.HasValue)
                    {
                        await using var cmdLoc = _dataSource.CreateCommand(@"
                            SELECT l.nombre AS localidad, pr.nombre AS provincia, pa.nombre AS pais
                            FROM admin.localidades l
                            JOIN admin.provincias pr ON l.id_provincia = pr.id
                            JOIN admin.paises pa ON pr.id_pais = pa.id
                            WHERE l.id = $1;");
                        cmdLoc.Parameters.AddWithValue(dto.IdLocalidad.Value);
                        await using var readerLoc = await cmdLoc.ExecuteReaderAsync();
                        if (await readerLoc.ReadAsync())
                        {
                            localidadNombre = readerLoc.GetString(0);
                            provinciaNombre = readerLoc.GetString(1);
                            paisNombre = readerLoc.GetString(2);
                        }
                    }

                    var alturaStr = !string.IsNullOrEmpty(dto.Altura) ? $" {dto.Altura}" : "";
                    computedDireccion = $"{dto.Calle}{alturaStr}".Trim();
                    if (!string.IsNullOrEmpty(localidadNombre))
                    {
                        computedDireccion += $", {localidadNombre}";
                    }
                    if (!string.IsNullOrEmpty(provinciaNombre))
                    {
                        computedDireccion += $", {provinciaNombre}";
                    }
                    if (!string.IsNullOrEmpty(paisNombre))
                    {
                        computedDireccion += $", {paisNombre}";
                    }
                }
                else
                {
                    computedDireccion = dto.Direccion;
                }

                await using var cmd = _dataSource.CreateCommand(@"
                    INSERT INTO admin.clientes (razon_social, cuit_dni, telefono, email, calle, altura, id_localidad, direccion, codigo, latitud, longitud)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                    RETURNING id, razon_social;");

                cmd.Parameters.AddWithValue(dto.RazonSocial);
                cmd.Parameters.AddWithValue(dto.CuitDni);
                cmd.Parameters.AddWithValue((object?)dto.Telefono ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.Email ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.Calle ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.Altura ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.IdLocalidad ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)computedDireccion ?? DBNull.Value);
                cmd.Parameters.AddWithValue(dto.Codigo);
                cmd.Parameters.AddWithValue((object?)dto.Latitud ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.Longitud ?? DBNull.Value);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return StatusCode(201, new 
                    { 
                        Id = reader.GetInt32(0), 
                        RazonSocial = reader.GetString(1), 
                        Message = "Cliente creado de manera exitosa en .NET 8" 
                    });
                }
                return BadRequest(new { Error = "Error inesperado al insertar cliente" });
            }
            catch (PostgresException ex) when (ex.SqlState == "23505" && ex.ConstraintName?.Contains("codigo") == true)
            {
                return BadRequest(new { Error = "El Código de Abonado / Facturación ingresado ya está asignado a otro cliente en la plataforma." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error en la transacción: {ex.Message}" });
            }
        }

        // 2. LISTADO DE CLIENTES (GET /api/clientes)
        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var list = new List<object>();
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT c.id, c.razon_social, c.cuit_dni, c.telefono, c.email, c.calle, c.altura, c.id_localidad, 
                           l.nombre AS localidad_nombre, pr.nombre AS provincia_nombre, pa.nombre AS pais_nombre, 
                           c.direccion, c.codigo, c.latitud, c.longitud 
                    FROM admin.clientes c
                    LEFT JOIN admin.localidades l ON c.id_localidad = l.id
                    LEFT JOIN admin.provincias pr ON l.id_provincia = pr.id
                    LEFT JOIN admin.paises pa ON pr.id_pais = pa.id
                    ORDER BY c.id DESC;");
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new
                    {
                        Id = reader.GetInt32(0),
                        RazonSocial = reader.GetString(1),
                        CuitDni = reader.GetString(2),
                        Telefono = reader.IsDBNull(3) ? null : reader.GetString(3),
                        Email = reader.IsDBNull(4) ? null : reader.GetString(4),
                        Calle = reader.IsDBNull(5) ? null : reader.GetString(5),
                        Altura = reader.IsDBNull(6) ? null : reader.GetString(6),
                        IdLocalidad = reader.IsDBNull(7) ? null : (int?)reader.GetInt32(7),
                        Localidad = reader.IsDBNull(8) ? null : reader.GetString(8),
                        Provincia = reader.IsDBNull(9) ? null : reader.GetString(9),
                        Pais = reader.IsDBNull(10) ? null : reader.GetString(10),
                        Direccion = reader.IsDBNull(11) ? null : reader.GetString(11),
                        Codigo = reader.IsDBNull(12) ? null : reader.GetString(12),
                        Latitud = reader.IsDBNull(13) ? null : (decimal?)reader.GetDecimal(13),
                        Longitud = reader.IsDBNull(14) ? null : (decimal?)reader.GetDecimal(14)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al listar clientes: {ex.Message}" });
            }
        }

        // 2.1. CONSULTA CLIENTE INDIVIDUAL POR ID (GET /api/clientes/{id})
        [HttpGet("{id}")]
        public async Task<IActionResult> GetById(int id)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT c.id, c.razon_social, c.cuit_dni, c.telefono, c.email, c.calle, c.altura, c.id_localidad, 
                           l.nombre AS localidad_nombre, pr.nombre AS provincia_nombre, pa.nombre AS pais_nombre, 
                           c.direccion, c.codigo, c.latitud, c.longitud 
                    FROM admin.clientes c
                    LEFT JOIN admin.localidades l ON c.id_localidad = l.id
                    LEFT JOIN admin.provincias pr ON l.id_provincia = pr.id
                    LEFT JOIN admin.paises pa ON pr.id_pais = pa.id
                    WHERE c.id = $1;");
                cmd.Parameters.AddWithValue(id);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return Ok(new
                    {
                        Id = reader.GetInt32(0),
                        RazonSocial = reader.GetString(1),
                        CuitDni = reader.GetString(2),
                        Telefono = reader.IsDBNull(3) ? null : reader.GetString(3),
                        Email = reader.IsDBNull(4) ? null : reader.GetString(4),
                        Calle = reader.IsDBNull(5) ? null : reader.GetString(5),
                        Altura = reader.IsDBNull(6) ? null : reader.GetString(6),
                        IdLocalidad = reader.IsDBNull(7) ? null : (int?)reader.GetInt32(7),
                        Localidad = reader.IsDBNull(8) ? null : reader.GetString(8),
                        Provincia = reader.IsDBNull(9) ? null : reader.GetString(9),
                        Pais = reader.IsDBNull(10) ? null : reader.GetString(10),
                        Direccion = reader.IsDBNull(11) ? null : reader.GetString(11),
                        Codigo = reader.IsDBNull(12) ? null : reader.GetString(12),
                        Latitud = reader.IsDBNull(13) ? null : (decimal?)reader.GetDecimal(13),
                        Longitud = reader.IsDBNull(14) ? null : (decimal?)reader.GetDecimal(14)
                    });
                }
                return NotFound(new { Error = $"El cliente con ID {id} no existe en el sistema." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al buscar cliente por ID: {ex.Message}" });
            }
        }

        // 2.2. CONSULTA CLIENTE INDIVIDUAL POR CÓDIGO DE FACTURACIÓN (GET /api/clientes/codigo/{codigo})
        [HttpGet("codigo/{codigo}")]
        public async Task<IActionResult> GetByCodigo(string codigo)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(codigo))
                {
                    return BadRequest(new { Error = "Debe proveer un código de facturación." });
                }

                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT c.id, c.razon_social, c.cuit_dni, c.telefono, c.email, c.calle, c.altura, c.id_localidad, 
                           l.nombre AS localidad_nombre, pr.nombre AS provincia_nombre, pa.nombre AS pais_nombre, 
                           c.direccion, c.codigo, c.latitud, c.longitud 
                    FROM admin.clientes c
                    LEFT JOIN admin.localidades l ON c.id_localidad = l.id
                    LEFT JOIN admin.provincias pr ON l.id_provincia = pr.id
                    LEFT JOIN admin.paises pa ON pr.id_pais = pa.id
                    WHERE c.codigo = $1;");
                cmd.Parameters.AddWithValue(codigo.Trim());

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    return Ok(new
                    {
                        Id = reader.GetInt32(0),
                        RazonSocial = reader.GetString(1),
                        CuitDni = reader.GetString(2),
                        Telefono = reader.IsDBNull(3) ? null : reader.GetString(3),
                        Email = reader.IsDBNull(4) ? null : reader.GetString(4),
                        Calle = reader.IsDBNull(5) ? null : reader.GetString(5),
                        Altura = reader.IsDBNull(6) ? null : reader.GetString(6),
                        IdLocalidad = reader.IsDBNull(7) ? null : (int?)reader.GetInt32(7),
                        Localidad = reader.IsDBNull(8) ? null : reader.GetString(8),
                        Provincia = reader.IsDBNull(9) ? null : reader.GetString(9),
                        Pais = reader.IsDBNull(10) ? null : reader.GetString(10),
                        Direccion = reader.IsDBNull(11) ? null : reader.GetString(11),
                        Codigo = reader.IsDBNull(12) ? null : reader.GetString(12),
                        Latitud = reader.IsDBNull(13) ? null : (decimal?)reader.GetDecimal(13),
                        Longitud = reader.IsDBNull(14) ? null : (decimal?)reader.GetDecimal(14)
                    });
                }
                return NotFound(new { Error = $"El cliente con código de facturación '{codigo}' no existe en el sistema." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al buscar cliente por código: {ex.Message}" });
            }
        }

        // GET /api/clientes/search?query=...
        [HttpGet("search")]
        public async Task<IActionResult> Search([FromQuery] string query)
        {
            if (string.IsNullOrWhiteSpace(query))
            {
                return BadRequest(new { Error = "Debe proveer un término de búsqueda en el parámetro 'query'." });
            }

            var wildcardQuery = $"%{query.Trim()}%";
            var list = new List<object>();

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT DISTINCT
                        c.id, c.razon_social, c.cuit_dni, c.telefono, c.email, c.calle, c.altura, c.id_localidad, 
                        l.nombre AS localidad_nombre, pr.nombre AS provincia_nombre, pa.nombre AS pais_nombre, 
                        c.direccion, c.codigo, c.latitud, c.longitud 
                    FROM admin.clientes c
                    LEFT JOIN admin.localidades l ON c.id_localidad = l.id
                    LEFT JOIN admin.provincias pr ON l.id_provincia = pr.id
                    LEFT JOIN admin.paises pa ON pr.id_pais = pa.id
                    LEFT JOIN admin.servicios_clientes s ON s.id_cliente = c.id
                    LEFT JOIN admin.equipos e ON s.id_equipo = e.id
                    WHERE c.razon_social ILIKE $1
                       OR c.direccion ILIKE $1
                       OR s.direccion_instalacion ILIKE $1
                       OR c.codigo ILIKE $1
                       OR e.mac::text ILIKE $1
                       OR s.ip_cm::text ILIKE $1
                       OR s.ip_cpe::text ILIKE $1
                    ORDER BY c.id DESC
                    LIMIT 100;");

                cmd.Parameters.AddWithValue(wildcardQuery);

                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new
                    {
                        Id = reader.GetInt32(0),
                        RazonSocial = reader.GetString(1),
                        CuitDni = reader.GetString(2),
                        Telefono = reader.IsDBNull(3) ? null : reader.GetString(3),
                        Email = reader.IsDBNull(4) ? null : reader.GetString(4),
                        Calle = reader.IsDBNull(5) ? null : reader.GetString(5),
                        Altura = reader.IsDBNull(6) ? null : reader.GetString(6),
                        IdLocalidad = reader.IsDBNull(7) ? null : (int?)reader.GetInt32(7),
                        Localidad = reader.IsDBNull(8) ? null : reader.GetString(8),
                        Provincia = reader.IsDBNull(9) ? null : reader.GetString(9),
                        Pais = reader.IsDBNull(10) ? null : reader.GetString(10),
                        Direccion = reader.IsDBNull(11) ? null : reader.GetString(11),
                        Codigo = reader.IsDBNull(12) ? null : reader.GetString(12),
                        Latitud = reader.IsDBNull(13) ? null : (decimal?)reader.GetDecimal(13),
                        Longitud = reader.IsDBNull(14) ? null : (decimal?)reader.GetDecimal(14)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error en la búsqueda de clientes: {ex.Message}" });
            }
        }

        // 3. ELIMINAR CLIENTE (DELETE /api/clientes/{id})
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                string razonSocial = "";

                // 1. Obtener datos del cliente para la validación
                await using (var cmdGet = _dataSource.CreateCommand("SELECT razon_social FROM admin.clientes WHERE id = $1;"))
                {
                    cmdGet.Parameters.AddWithValue(id);
                    var res = await cmdGet.ExecuteScalarAsync();
                    if (res == null)
                    {
                        return NotFound(new { Error = $"El cliente con ID {id} no fue encontrado en la base de datos." });
                    }
                    razonSocial = res.ToString() ?? "";
                }

                // 2. Validar si existen servicios asociados en admin.servicios_clientes
                int servicesCount = 0;
                await using (var cmdCheck = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.servicios_clientes WHERE id_cliente = $1;"))
                {
                    cmdCheck.Parameters.AddWithValue(id);
                    servicesCount = (int)(await cmdCheck.ExecuteScalarAsync() ?? 0);
                }

                if (servicesCount > 0)
                {
                    return BadRequest(new { Error = $"No se puede eliminar el cliente '{razonSocial}' porque posee {servicesCount} servicio(s) de internet / aprovisionamiento registrados en la plataforma. Por motivos de integridad y auditoría, debe eliminar los servicios asociados primero." });
                }

                // 3. Proceder con la eliminación física
                await using (var cmdDel = _dataSource.CreateCommand("DELETE FROM admin.clientes WHERE id = $1;"))
                {
                    cmdDel.Parameters.AddWithValue(id);
                    await cmdDel.ExecuteNonQueryAsync();
                }

                return Ok(new { Id = id, Message = "Abonado comercial eliminado con éxito de la plataforma." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503") // Violación de llave foránea restrict
            {
                return BadRequest(new { Error = "No se puede eliminar el cliente porque posee recursos o vinculaciones de red activos." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar abonado: {ex.Message}" });
            }
        }

        // 4. MODIFICAR CLIENTE (PUT /api/clientes/{id})
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] ClienteCreateDto dto)
        {
            // Sanitizar y recortar espacios en blanco
            dto.RazonSocial = dto.RazonSocial?.Trim() ?? "";
            dto.CuitDni = dto.CuitDni?.Trim().Replace(".", "") ?? ""; // Eliminar puntos de formato en CUIT/DNI
            dto.Telefono = dto.Telefono?.Trim();
            dto.Email = dto.Email?.Trim();
            dto.Calle = dto.Calle?.Trim();
            dto.Altura = dto.Altura?.Trim();
            dto.Pais = string.IsNullOrWhiteSpace(dto.Pais) ? "Argentina" : dto.Pais.Trim();
            dto.Codigo = dto.Codigo?.Trim();
            dto.Direccion = dto.Direccion?.Trim();

            // 1. Validaciones para Razón Social
            if (string.IsNullOrWhiteSpace(dto.RazonSocial) || dto.RazonSocial.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new { Error = "La Razón Social / Nombre Completo es obligatorio y no puede ser genérico." });
            }
            if (dto.RazonSocial.Length < 3 || dto.RazonSocial.Length > 150)
            {
                return BadRequest(new { Error = "La Razón Social / Nombre Completo debe tener entre 3 y 150 caracteres." });
            }

            // 2. Validaciones para CUIT / DNI
            if (string.IsNullOrWhiteSpace(dto.CuitDni) || dto.CuitDni.Equals("string", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(new { Error = "El CUIT o DNI es obligatorio y no puede ser genérico." });
            }
            
            var cuitDniRegex = new System.Text.RegularExpressions.Regex(@"^^(\d{7,8}|\d{11}|\d{2}-\d{8}-\d{1})$$");
            if (!cuitDniRegex.IsMatch(dto.CuitDni))
            {
                return BadRequest(new { Error = "Formato de CUIT/DNI no válido. Debe ingresar un DNI (7 u 8 números) o un CUIT (11 números sin guiones, o con guiones en formato XX-XXXXXXXX-X)." });
            }

            // 3. Validaciones de Email
            if (!string.IsNullOrEmpty(dto.Email))
            {
                var emailRegex = new System.Text.RegularExpressions.Regex(@"^^[^\s@]+@[^\s@]+\.[^\s@]+$$");
                if (!emailRegex.IsMatch(dto.Email))
                {
                    return BadRequest(new { Error = "La dirección de correo electrónico ingresada posee un formato inválido." });
                }
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.clientes 
                    SET razon_social = $1, 
                        cuit_dni = $2, 
                        telefono = $3, 
                        email = $4, 
                        calle = $5, 
                        altura = $6, 
                        id_localidad = $7, 
                        codigo = $8, 
                        direccion = $9, 
                        latitud = $10, 
                        longitud = $11
                    WHERE id = $12
                    RETURNING id;");

                cmd.Parameters.AddWithValue(dto.RazonSocial);
                cmd.Parameters.AddWithValue(dto.CuitDni);
                cmd.Parameters.AddWithValue(dto.Telefono ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue(dto.Email ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue(dto.Calle ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue(dto.Altura ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue(dto.IdLocalidad ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue(dto.Codigo ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue(dto.Direccion ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue(dto.Latitud ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue(dto.Longitud ?? (object)DBNull.Value);
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null)
                {
                    return NotFound(new { Error = $"El cliente con ID {id} no fue encontrado en la base de datos." });
                }

                return Ok(new { Id = id, Message = "Datos de abonado actualizados con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23505") // Uniqueness constraint violation
            {
                if (ex.ConstraintName?.Contains("cuit_dni") == true)
                    return BadRequest(new { Error = "Ya existe otro abonado comercial registrado con ese mismo CUIT o DNI." });
                if (ex.ConstraintName?.Contains("codigo") == true)
                    return BadRequest(new { Error = "Ya existe otro abonado comercial registrado con ese mismo código de facturación único." });
                return BadRequest(new { Error = "Ocurrió un conflicto de duplicidad al intentar actualizar el cliente." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al actualizar datos de abonado: {ex.Message}" });
            }
        }

        // 5. OBTENER LOGS DE AUDITORÍA (GET /api/clientes/logs)
        [HttpGet("logs")]
        public async Task<IActionResult> GetAuditLogs([FromQuery] int? idCliente, [FromQuery] string? query)
        {
            var list = new List<object>();
            try
            {
                string sql = @"
                    SELECT a.id, a.id_cliente, a.nombre_cliente, a.fecha, a.usuario, a.accion, a.detalle, a.valores_anteriores::text, a.valores_nuevos::text
                    FROM admin.auditoria_clientes a
                    WHERE 1=1";

                var parameters = new List<object>();
                int paramIndex = 1;

                if (idCliente.HasValue)
                {
                    sql += $" AND a.id_cliente = ${paramIndex++}";
                    parameters.Add(idCliente.Value);
                }

                if (!string.IsNullOrWhiteSpace(query))
                {
                    string wildcard = $"%{query.Trim()}%";
                    sql += $" AND (a.nombre_cliente ILIKE ${paramIndex} OR a.usuario ILIKE ${paramIndex} OR a.accion ILIKE ${paramIndex} OR a.detalle ILIKE ${paramIndex})";
                    parameters.Add(wildcard);
                }

                sql += " ORDER BY a.fecha DESC LIMIT 150;";

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
                        Id = reader.GetInt64(0),
                        IdCliente = reader.IsDBNull(1) ? null : (int?)reader.GetInt32(1),
                        NombreCliente = reader.IsDBNull(2) ? null : reader.GetString(2),
                        Fecha = reader.GetDateTime(3),
                        Usuario = reader.GetString(4),
                        Accion = reader.GetString(5),
                        Detalle = reader.GetString(6),
                        ValoresAnteriores = reader.IsDBNull(7) ? null : reader.GetString(7),
                        ValoresNuevos = reader.IsDBNull(8) ? null : reader.GetString(8)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al consultar logs de auditoría: {ex.Message}" });
            }
        }
    }
}
