using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class RedController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;

        public RedController(NpgsqlDataSource dataSource)
        {
            _dataSource = dataSource;
        }

        public class CmtsCreateDto
        {
            public string Nombre { get; set; } = null!;
            public string IpControl { get; set; } = null!; // Alinear con el payload 'ipControl' del React Frontend
            public string? Descripcion { get; set; }
        }

        public class SubredCreateDto
        {
            public int IdCmts { get; set; }
            public string Nombre { get; set; } = null!;
            public string Cidr { get; set; } = null!;
            public string Gateway { get; set; } = null!;
            public string Tipo { get; set; } = null!; // CM o CPE
            public string? Descripcion { get; set; }
        }

        public class PoolCreateDto
        {
            public int IdSubred { get; set; }
            public string RangoInicio { get; set; } = null!;
            public string RangoFin { get; set; } = null!;
            public int? IdPaquete { get; set; }
            public string? ClientClass { get; set; }
            public bool EsEstatico { get; set; }
        }

        public class PaqueteCreateDto
        {
            public string Nombre { get; set; } = null!;
            public int VelocidadBajadaKbps { get; set; }
            public int VelocidadSubidaKbps { get; set; }
            public string? Bootfile { get; set; }
            public string? Dhcp4ClientClass { get; set; }
        }

        // =========================================================================
        // --- ENDPOINTS HTTP GET (LISTAR RECURSOS DE RED) ---
        // =========================================================================

        // 1. LISTAR CMTSs (GET /api/red/cmts)
        [HttpGet("cmts")]
        public async Task<IActionResult> GetCmtsList()
        {
            try
            {
                var list = new List<object>();
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT id, nombre, ip_relay::text AS ip_control, descripcion 
                    FROM admin.cmts 
                    ORDER BY id;");
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        IpControl = reader.GetString(2),
                        Descripcion = reader.IsDBNull(3) ? null : reader.GetString(3)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al obtener lista de CMTS: {ex.Message}" });
            }
        }

        // 2. LISTAR SUBREDES (GET /api/red/subredes)
        [HttpGet("subredes")]
        public async Task<IActionResult> GetSubredesList()
        {
            try
            {
                var list = new List<object>();
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT s.id, s.id_cmts, c.nombre AS cmts_nombre, s.nombre, s.cidr::text, s.gateway::text, s.tipo, s.descripcion 
                    FROM admin.subredes s
                    JOIN admin.cmts c ON s.id_cmts = c.id
                    ORDER BY s.id;");
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new
                    {
                        Id = reader.GetInt32(0),
                        IdCmts = reader.GetInt32(1),
                        Cmts = reader.GetString(2),
                        Nombre = reader.GetString(3),
                        Cidr = reader.GetString(4),
                        Gateway = reader.GetString(5),
                        Tipo = reader.GetString(6),
                        Descripcion = reader.IsDBNull(7) ? null : reader.GetString(7)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al obtener lista de subredes: {ex.Message}" });
            }
        }

        // 3. LISTAR POOLS DHCP (GET /api/red/pools)
        [HttpGet("pools")]
        public async Task<IActionResult> GetPoolsList()
        {
            try
            {
                var list = new List<object>();
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT 
                        p.id, 
                        p.id_subred, 
                        s.nombre AS subred_nombre, 
                        host(p.rango_inicio), 
                        host(p.rango_fin), 
                        p.id_paquete,
                        ((p.rango_fin - p.rango_inicio) + 1)::int AS total_ips,
                        COALESCE((
                            SELECT COUNT(*)::int 
                            FROM public.lease4 l 
                            WHERE l.state = 0 
                              AND l.expire > CURRENT_TIMESTAMP 
                              AND l.address >= (p.rango_inicio - '0.0.0.0'::inet)::bigint
                              AND l.address <= (p.rango_fin - '0.0.0.0'::inet)::bigint
                        ), 0)::int AS ips_asignadas,
                        p.es_estatico,
                        p.client_class
                    FROM admin.pools p
                    JOIN admin.subredes s ON p.id_subred = s.id
                    ORDER BY p.id;");
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new
                    {
                        Id = reader.GetInt32(0),
                        IdSubred = reader.GetInt32(1),
                        Subred = reader.GetString(2),
                        RangoInicio = reader.GetString(3),
                        RangoFin = reader.GetString(4),
                        IdPaquete = reader.IsDBNull(5) ? null : (int?)reader.GetInt32(5),
                        TotalIps = reader.GetInt32(6),
                        IpsAsignadas = reader.GetInt32(7),
                        EsEstatico = reader.GetBoolean(8),
                        ClientClass = reader.IsDBNull(9) ? null : reader.GetString(9)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al obtener lista de pools DHCP: {ex.Message}" });
            }
        }

        // 4. LISTAR PLANES / PAQUETES (GET /api/red/paquetes)
        [HttpGet("paquetes")]
        public async Task<IActionResult> GetPaquetesList()
        {
            try
            {
                var list = new List<object>();
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT id, nombre, velocidad_bajada_kbps, velocidad_subida_kbps, bootfile, dhcp4_client_class, estado 
                    FROM admin.paquetes 
                    ORDER BY id;");
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    list.Add(new
                    {
                        Id = reader.GetInt32(0),
                        Nombre = reader.GetString(1),
                        VelocidadBajadaKbps = reader.GetInt32(2),
                        VelocidadSubidaKbps = reader.GetInt32(3),
                        Bootfile = reader.IsDBNull(4) ? null : reader.GetString(4),
                        Dhcp4ClientClass = reader.IsDBNull(5) ? null : reader.GetString(5),
                        Estado = reader.GetBoolean(6)
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al obtener lista de planes comerciales: {ex.Message}" });
            }
        }

        // =========================================================================
        // --- ENDPOINTS HTTP POST (CREACIÓN) ---
        // =========================================================================

        // --- CMTS ---
        [HttpPost("cmts")]
        public async Task<IActionResult> CreateCmts([FromBody] CmtsCreateDto dto)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    INSERT INTO admin.cmts (nombre, ip_relay, descripcion)
                    VALUES ($1, $2::inet, $3)
                    RETURNING id;");
                cmd.Parameters.AddWithValue(dto.Nombre);
                cmd.Parameters.AddWithValue(dto.IpControl);
                cmd.Parameters.AddWithValue((object?)dto.Descripcion ?? DBNull.Value);

                var id = await cmd.ExecuteScalarAsync();
                return StatusCode(201, new { Id = id, Message = "CMTS ruteado con éxito" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al registrar CMTS: {ex.Message}" });
            }
        }

        // --- SUBREDES ---
        [HttpPost("subredes")]
        public async Task<IActionResult> CreateSubred([FromBody] SubredCreateDto dto)
        {
            if (dto.Tipo != "CM" && dto.Tipo != "CPE")
            {
                return BadRequest(new { Error = "Tipo de subred inválido. Debe ser 'CM' (Gestión) o 'CPE' (Navegación)" });
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    INSERT INTO admin.subredes (id_cmts, nombre, cidr, gateway, tipo, descripcion)
                    VALUES ($1, $2, network($3::inet), $4::inet, $5, $6)
                    RETURNING id;");
                cmd.Parameters.AddWithValue(dto.IdCmts);
                cmd.Parameters.AddWithValue(dto.Nombre);
                cmd.Parameters.AddWithValue(dto.Cidr);
                cmd.Parameters.AddWithValue(dto.Gateway);
                cmd.Parameters.AddWithValue(dto.Tipo);
                cmd.Parameters.AddWithValue((object?)dto.Descripcion ?? DBNull.Value);

                var id = await cmd.ExecuteScalarAsync();
                await SyncKeaConfigAsync(_dataSource);
                return StatusCode(201, new { Id = id, Message = "Subred ruteada con éxito" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al ruterar subred: {ex.Message}" });
            }
        }

        // --- POOLS ---
        [HttpPost("pools")]
        public async Task<IActionResult> CreatePool([FromBody] PoolCreateDto dto)
        {
            try
            {
                // 1. Validar que la subred existe
                await using (var cmdCheckSub = _dataSource.CreateCommand(@"
                    SELECT cidr::text FROM admin.subredes WHERE id = $1;"))
                {
                    cmdCheckSub.Parameters.AddWithValue(dto.IdSubred);
                    var cidrObj = await cmdCheckSub.ExecuteScalarAsync();
                    if (cidrObj == null)
                    {
                        return BadRequest(new { Error = "La subred seleccionada no existe." });
                    }
                }

                // 2. Validar que el rango de IPs esté dentro de los límites de la subred CIDR
                await using (var cmdCheckBounds = _dataSource.CreateCommand(@"
                    SELECT COUNT(*)::int FROM admin.subredes 
                    WHERE id = $1 AND ($2::inet <<= cidr AND $3::inet <<= cidr);"))
                {
                    cmdCheckBounds.Parameters.AddWithValue(dto.IdSubred);
                    cmdCheckBounds.Parameters.AddWithValue(dto.RangoInicio.Trim());
                    cmdCheckBounds.Parameters.AddWithValue(dto.RangoFin.Trim());
                    int countBounds = (int)(await cmdCheckBounds.ExecuteScalarAsync() ?? 0);
                    if (countBounds == 0)
                    {
                        return BadRequest(new { Error = "El rango de IPs ingresado está fuera de los límites de la subred." });
                    }
                }

                // 3. Validar que no haya solapamiento con otros pools de la misma subred
                await using (var cmdCheckOverlap = _dataSource.CreateCommand(@"
                    SELECT COUNT(*)::int FROM admin.pools
                    WHERE id_subred = $1
                      AND (rango_inicio <= $3::inet AND $2::inet <= rango_fin);"))
                {
                    cmdCheckOverlap.Parameters.AddWithValue(dto.IdSubred);
                    cmdCheckOverlap.Parameters.AddWithValue(dto.RangoInicio.Trim());
                    cmdCheckOverlap.Parameters.AddWithValue(dto.RangoFin.Trim());
                    int countOverlap = (int)(await cmdCheckOverlap.ExecuteScalarAsync() ?? 0);
                    if (countOverlap > 0)
                    {
                        return BadRequest(new { Error = "El rango de IPs se solapa con otro rango ya existente en esta subred." });
                    }
                }

                await using var cmd = _dataSource.CreateCommand(@"
                    INSERT INTO admin.pools (id_subred, rango_inicio, rango_fin, id_paquete, client_class, es_estatico)
                    VALUES ($1, $2::inet, $3::inet, $4, $5, $6)
                    RETURNING id;");
                cmd.Parameters.AddWithValue(dto.IdSubred);
                cmd.Parameters.AddWithValue(dto.RangoInicio);
                cmd.Parameters.AddWithValue(dto.RangoFin);
                cmd.Parameters.AddWithValue((object?)dto.IdPaquete ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.ClientClass ?? DBNull.Value);
                cmd.Parameters.AddWithValue(dto.EsEstatico);

                var id = await cmd.ExecuteScalarAsync();
                await SyncKeaConfigAsync(_dataSource);
                return StatusCode(201, new { Id = id, Message = "Pool DHCP registrado y amarrado con éxito" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al configurar pool DHCP: {ex.Message}" });
            }
        }

        // --- PAQUETES/PLANES ---
        [HttpPost("paquetes")]
        public async Task<IActionResult> CreatePaquete([FromBody] PaqueteCreateDto dto)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    INSERT INTO admin.paquetes (nombre, velocidad_bajada_kbps, velocidad_subida_kbps, bootfile, dhcp4_client_class)
                    VALUES ($1, $2, $3, $4, $5)
                    RETURNING id;");
                cmd.Parameters.AddWithValue(dto.Nombre);
                cmd.Parameters.AddWithValue(dto.VelocidadBajadaKbps);
                cmd.Parameters.AddWithValue(dto.VelocidadSubidaKbps);
                cmd.Parameters.AddWithValue((object?)dto.Bootfile ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.Dhcp4ClientClass ?? DBNull.Value);

                var id = await cmd.ExecuteScalarAsync();
                return StatusCode(201, new { Id = id, Message = "Plan de internet registrado con éxito" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al registrar plan de internet: {ex.Message}" });
            }
        }

        // =========================================================================
        // --- ENDPOINTS HTTP DELETE ---
        // =========================================================================

        [HttpDelete("cmts/{id}")]
        public async Task<IActionResult> DeleteCmts(int id)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand("DELETE FROM admin.cmts WHERE id = $1 RETURNING id;");
                cmd.Parameters.AddWithValue(id);
                var result = await cmd.ExecuteScalarAsync();
                if (result == null) return NotFound(new { Error = "El CMTS solicitado no existe en la base de datos." });
                return Ok(new { Id = id, Message = "CMTS retirado del ruteo de red con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503")
            {
                return BadRequest(new { Error = "No se puede eliminar el CMTS porque tiene subredes o suscripciones de clientes activas amarradas a él." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar CMTS: {ex.Message}" });
            }
        }

        [HttpDelete("subredes/{id}")]
        public async Task<IActionResult> DeleteSubred(int id)
        {
            try
            {
                string nombre = "";
                string cidr = "";

                // 1. Obtener datos de la subred para validaciones
                await using (var cmdGet = _dataSource.CreateCommand("SELECT nombre, cidr::text FROM admin.subredes WHERE id = $1;"))
                {
                    cmdGet.Parameters.AddWithValue(id);
                    await using var reader = await cmdGet.ExecuteReaderAsync();
                    if (await reader.ReadAsync())
                    {
                        nombre = reader.GetString(0);
                        cidr = reader.GetString(1);
                    }
                    else
                    {
                        return NotFound(new { Error = "La subred solicitada no existe." });
                    }
                }

                // 2. Validar si existen pools DHCP asociados en admin.pools
                int poolsCount = 0;
                await using (var cmdCheckPools = _dataSource.CreateCommand("SELECT COUNT(*)::int FROM admin.pools WHERE id_subred = $1;"))
                {
                    cmdCheckPools.Parameters.AddWithValue(id);
                    poolsCount = (int)(await cmdCheckPools.ExecuteScalarAsync() ?? 0);
                }

                if (poolsCount > 0)
                {
                    return BadRequest(new { Error = $"No se puede eliminar la subred '{nombre}' porque tiene {poolsCount} rango(s) de asignación (pools DHCP) configurados. Por favor, elimina los pools primero." });
                }

                // 3. Validar si existen servicios de clientes con IPs asignadas dentro del rango CIDR de esta subred
                int activeClientsCount = 0;
                await using (var cmdCheckClients = _dataSource.CreateCommand(@"
                    SELECT COUNT(*)::int 
                    FROM admin.servicios_clientes 
                    WHERE (ip_cm <<= $1::cidr OR ip_cpe <<= $1::cidr);"))
                {
                    cmdCheckClients.Parameters.AddWithValue(cidr);
                    activeClientsCount = (int)(await cmdCheckClients.ExecuteScalarAsync() ?? 0);
                }

                if (activeClientsCount > 0)
                {
                    return BadRequest(new { Error = $"No se puede eliminar la subred '{nombre}' ({cidr}) porque existen {activeClientsCount} servicio(s) de abonado con direcciones IP activas asignadas dentro de este rango." });
                }

                // 4. Proceder con la eliminación física
                await using (var cmdDel = _dataSource.CreateCommand("DELETE FROM admin.subredes WHERE id = $1;"))
                {
                    cmdDel.Parameters.AddWithValue(id);
                    await cmdDel.ExecuteNonQueryAsync();
                }

                await SyncKeaConfigAsync(_dataSource);
                return Ok(new { Id = id, Message = "Subred eliminada con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503")
            {
                return BadRequest(new { Error = "No se puede eliminar esta subred porque se encuentra vinculada a recursos de red activos." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar subred: {ex.Message}" });
            }
        }

        [HttpDelete("pools/{id}")]
        public async Task<IActionResult> DeletePool(int id)
        {
            try
            {
                // 1. Obtener el rango del pool antes de eliminar para contar leases activos
                string rangoInicioStr = "";
                string rangoFinStr = "";
                await using (var cmdGetRange = _dataSource.CreateCommand(@"
                    SELECT host(rango_inicio), host(rango_fin) FROM admin.pools WHERE id = $1;"))
                {
                    cmdGetRange.Parameters.AddWithValue(id);
                    await using var reader = await cmdGetRange.ExecuteReaderAsync();
                    if (await reader.ReadAsync())
                    {
                        rangoInicioStr = reader.GetString(0);
                        rangoFinStr = reader.GetString(1);
                    }
                    else
                    {
                        return NotFound(new { Error = "El pool DHCP solicitado no existe." });
                    }
                }

                // 2. Contar leases activos en public.lease4 para ese rango
                int activeLeasesCount = 0;
                await using (var cmdCountLeases = _dataSource.CreateCommand(@"
                    SELECT COUNT(*)::int 
                    FROM public.lease4 l 
                    WHERE l.state = 0 
                      AND l.expire > CURRENT_TIMESTAMP 
                      AND l.address >= ($1::inet - '0.0.0.0'::inet)::bigint
                      AND l.address <= ($2::inet - '0.0.0.0'::inet)::bigint;"))
                {
                    cmdCountLeases.Parameters.AddWithValue(rangoInicioStr);
                    cmdCountLeases.Parameters.AddWithValue(rangoFinStr);
                    activeLeasesCount = (int)(await cmdCountLeases.ExecuteScalarAsync() ?? 0);
                }

                if (activeLeasesCount > 0)
                {
                    return BadRequest(new { Error = $"No se puede eliminar este pool porque tiene {activeLeasesCount} IPs activas asignadas a clientes. Primero debe migrar o apagar estas conexiones." });
                }

                await using var cmd = _dataSource.CreateCommand("DELETE FROM admin.pools WHERE id = $1 RETURNING id;");
                cmd.Parameters.AddWithValue(id);
                var result = await cmd.ExecuteScalarAsync();
                await SyncKeaConfigAsync(_dataSource);
                return Ok(new { Id = id, Message = "Pool DHCP de red eliminado con éxito." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar pool DHCP: {ex.Message}" });
            }
        }

        [HttpDelete("paquetes/{id}")]
        public async Task<IActionResult> DeletePaquete(int id)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand("DELETE FROM admin.paquetes WHERE id = $1 RETURNING id;");
                cmd.Parameters.AddWithValue(id);
                var result = await cmd.ExecuteScalarAsync();
                if (result == null) return NotFound(new { Error = "El plan de velocidad solicitado no existe." });
                return Ok(new { Id = id, Message = "Plan de internet comercial eliminado con éxito." });
            }
            catch (PostgresException ex) when (ex.SqlState == "23503")
            {
                return BadRequest(new { Error = "No se puede eliminar este plan porque existen suscripciones de abonados activas o pools DHCP configurados para esta velocidad." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar plan de velocidad: {ex.Message}" });
            }
        }

        // =========================================================================
        // --- ENDPOINTS HTTP PUT (MODIFICACIÓN DE RED) ---
        // =========================================================================

        [HttpPut("cmts/{id}")]
        public async Task<IActionResult> UpdateCmts(int id, [FromBody] CmtsCreateDto dto)
        {
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.cmts 
                    SET nombre = $1, ip_relay = $2::inet, descripcion = $3
                    WHERE id = $4
                    RETURNING id;");
                cmd.Parameters.AddWithValue(dto.Nombre.Trim());
                cmd.Parameters.AddWithValue(dto.IpControl.Trim());
                cmd.Parameters.AddWithValue((object?)dto.Descripcion?.Trim() ?? DBNull.Value);
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null) return NotFound(new { Error = "El CMTS solicitado no existe." });
                return Ok(new { Id = id, Message = "CMTS actualizado con éxito en la red." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al actualizar CMTS: {ex.Message}" });
            }
        }

        [HttpPut("subredes/{id}")]
        public async Task<IActionResult> UpdateSubred(int id, [FromBody] SubredCreateDto dto)
        {
            try
            {
                // 1. Validar que todos los pools existentes queden contenidos dentro del nuevo CIDR ruteado
                int outOfBoundsPoolsCount = 0;
                await using (var cmdCheckBounds = _dataSource.CreateCommand(@"
                    SELECT COUNT(*)::int FROM admin.pools
                    WHERE id_subred = $1
                      AND NOT (rango_inicio <<= network($2::inet) AND rango_fin <<= network($2::inet));"))
                {
                    cmdCheckBounds.Parameters.AddWithValue(id);
                    cmdCheckBounds.Parameters.AddWithValue(dto.Cidr.Trim());
                    outOfBoundsPoolsCount = (int)(await cmdCheckBounds.ExecuteScalarAsync() ?? 0);
                }

                if (outOfBoundsPoolsCount > 0)
                {
                    return BadRequest(new { Error = $"No se puede cambiar el CIDR de la subred a '{dto.Cidr}' porque hay {outOfBoundsPoolsCount} rango(s) de pool DHCP ya configurados que quedarían fuera de los límites de este nuevo bloque de red." });
                }

                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.subredes 
                    SET id_cmts = $1, nombre = $2, cidr = network($3::inet), gateway = $4::inet, tipo = $5, descripcion = $6
                    WHERE id = $7
                    RETURNING id;");
                cmd.Parameters.AddWithValue(dto.IdCmts);
                cmd.Parameters.AddWithValue(dto.Nombre.Trim());
                cmd.Parameters.AddWithValue(dto.Cidr.Trim());
                cmd.Parameters.AddWithValue(dto.Gateway.Trim());
                cmd.Parameters.AddWithValue(dto.Tipo.Trim());
                cmd.Parameters.AddWithValue((object?)dto.Descripcion?.Trim() ?? DBNull.Value);
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null) return NotFound(new { Error = "La subred solicitada no existe." });
                await SyncKeaConfigAsync(_dataSource);
                return Ok(new { Id = id, Message = "Subred ruteada actualizada con éxito." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al actualizar subred: {ex.Message}" });
            }
        }

        [HttpPut("pools/{id}")]
        public async Task<IActionResult> UpdatePool(int id, [FromBody] PoolCreateDto dto)
        {
            try
            {
                // 1. Obtener los valores actuales (rango anterior y clase anterior)
                string oldInicioStr = "";
                string oldFinStr = "";
                string? oldClientClass = null;
                await using (var cmdGetOld = _dataSource.CreateCommand(@"
                    SELECT host(rango_inicio), host(rango_fin), client_class FROM admin.pools WHERE id = $1;"))
                {
                    cmdGetOld.Parameters.AddWithValue(id);
                    await using var reader = await cmdGetOld.ExecuteReaderAsync();
                    if (await reader.ReadAsync())
                    {
                        oldInicioStr = reader.GetString(0);
                        oldFinStr = reader.GetString(1);
                        oldClientClass = reader.IsDBNull(2) ? null : reader.GetString(2);
                    }
                    else
                    {
                        return NotFound(new { Error = "El pool DHCP solicitado no existe." });
                    }
                }

                // 2. Contar leases que quedarán EXCLUIDOS si el rango se achica
                int excludedLeasesCount = 0;
                await using (var cmdCheckShrink = _dataSource.CreateCommand(@"
                    SELECT COUNT(*)::int 
                    FROM public.lease4 l 
                    WHERE l.state = 0 
                      AND l.expire > CURRENT_TIMESTAMP 
                      AND l.address >= ($1::inet - '0.0.0.0'::inet)::bigint
                      AND l.address <= ($2::inet - '0.0.0.0'::inet)::bigint
                      AND NOT (
                        l.address >= ($3::inet - '0.0.0.0'::inet)::bigint
                        AND l.address <= ($4::inet - '0.0.0.0'::inet)::bigint
                      );"))
                {
                    cmdCheckShrink.Parameters.AddWithValue(oldInicioStr);
                    cmdCheckShrink.Parameters.AddWithValue(oldFinStr);
                    cmdCheckShrink.Parameters.AddWithValue(dto.RangoInicio.Trim());
                    cmdCheckShrink.Parameters.AddWithValue(dto.RangoFin.Trim());
                    excludedLeasesCount = (int)(await cmdCheckShrink.ExecuteScalarAsync() ?? 0);
                }

                if (excludedLeasesCount > 0)
                {
                    return BadRequest(new { Error = $"No se puede modificar el rango del pool porque hay {excludedLeasesCount} clientes activos con IPs asignadas en el área que desea quitar. Achicar el pool desconectaría a estos usuarios." });
                }

                // 3. Validar si la clase del cliente DHCP cambia, pero hay leases activos
                if (oldClientClass != dto.ClientClass)
                {
                    int totalActiveLeases = 0;
                    await using (var cmdCountAllActive = _dataSource.CreateCommand(@"
                        SELECT COUNT(*)::int 
                        FROM public.lease4 l 
                        WHERE l.state = 0 
                          AND l.expire > CURRENT_TIMESTAMP 
                          AND l.address >= ($1::inet - '0.0.0.0'::inet)::bigint
                          AND l.address <= ($2::inet - '0.0.0.0'::inet)::bigint;"))
                    {
                        cmdCountAllActive.Parameters.AddWithValue(oldInicioStr);
                        cmdCountAllActive.Parameters.AddWithValue(oldFinStr);
                        totalActiveLeases = (int)(await cmdCountAllActive.ExecuteScalarAsync() ?? 0);
                    }

                    if (totalActiveLeases > 0)
                    {
                        return BadRequest(new { Error = $"No se puede cambiar el Grupo de Pools / Clase de '{oldClientClass ?? "Sin Clase"}' a '{dto.ClientClass ?? "Sin Clase"}' porque el pool tiene {totalActiveLeases} clientes activos. Cambiar el grupo desconectará a estos usuarios en su próxima renovación de IP." });
                    }
                }

                // 4. Validar que la subred existe
                await using (var cmdCheckSub = _dataSource.CreateCommand(@"
                    SELECT cidr::text FROM admin.subredes WHERE id = $1;"))
                {
                    cmdCheckSub.Parameters.AddWithValue(dto.IdSubred);
                    var cidrObj = await cmdCheckSub.ExecuteScalarAsync();
                    if (cidrObj == null)
                    {
                        return BadRequest(new { Error = "La subred seleccionada no existe." });
                    }
                }

                // 5. Validar que el rango de IPs esté dentro de los límites de la subred CIDR
                await using (var cmdCheckBounds = _dataSource.CreateCommand(@"
                    SELECT COUNT(*)::int FROM admin.subredes 
                    WHERE id = $1 AND ($2::inet <<= cidr AND $3::inet <<= cidr);"))
                {
                    cmdCheckBounds.Parameters.AddWithValue(dto.IdSubred);
                    cmdCheckBounds.Parameters.AddWithValue(dto.RangoInicio.Trim());
                    cmdCheckBounds.Parameters.AddWithValue(dto.RangoFin.Trim());
                    int countBounds = (int)(await cmdCheckBounds.ExecuteScalarAsync() ?? 0);
                    if (countBounds == 0)
                    {
                        return BadRequest(new { Error = "El rango de IPs ingresado está fuera de los límites de la subred." });
                    }
                }

                // 6. Validar que no haya solapamiento con otros pools de la misma subred (excluyendo el actual)
                await using (var cmdCheckOverlap = _dataSource.CreateCommand(@"
                    SELECT COUNT(*)::int FROM admin.pools
                    WHERE id_subred = $1 AND id != $4
                      AND (rango_inicio <= $3::inet AND $2::inet <= rango_fin);"))
                {
                    cmdCheckOverlap.Parameters.AddWithValue(dto.IdSubred);
                    cmdCheckOverlap.Parameters.AddWithValue(dto.RangoInicio.Trim());
                    cmdCheckOverlap.Parameters.AddWithValue(dto.RangoFin.Trim());
                    cmdCheckOverlap.Parameters.AddWithValue(id);
                    int countOverlap = (int)(await cmdCheckOverlap.ExecuteScalarAsync() ?? 0);
                    if (countOverlap > 0)
                    {
                        return BadRequest(new { Error = "El rango de IPs se solapa con otro rango ya existente en esta subred." });
                    }
                }

                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.pools 
                    SET id_subred = $1, rango_inicio = $2::inet, rango_fin = $3::inet, id_paquete = $4, client_class = $5, es_estatico = $6
                    WHERE id = $7
                    RETURNING id;");
                cmd.Parameters.AddWithValue(dto.IdSubred);
                cmd.Parameters.AddWithValue(dto.RangoInicio.Trim());
                cmd.Parameters.AddWithValue(dto.RangoFin.Trim());
                cmd.Parameters.AddWithValue((object?)dto.IdPaquete ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.ClientClass ?? DBNull.Value);
                cmd.Parameters.AddWithValue(dto.EsEstatico);
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null) return NotFound(new { Error = "El pool DHCP solicitado no existe." });
                await SyncKeaConfigAsync(_dataSource);
                return Ok(new { Id = id, Message = "Pool DHCP de red actualizado con éxito." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al actualizar pool DHCP: {ex.Message}" });
            }
        }

        [HttpPut("paquetes/{id}")]
        public async Task<IActionResult> UpdatePaquete(int id, [FromBody] PaqueteCreateDto dto)
        {
            try
            {
                // 1. Obtener la clase de cliente actual de este paquete
                string? oldClientClass = null;
                await using (var cmdGetOld = _dataSource.CreateCommand(@"
                    SELECT dhcp4_client_class FROM admin.paquetes WHERE id = $1;"))
                {
                    cmdGetOld.Parameters.AddWithValue(id);
                    var resClass = await cmdGetOld.ExecuteScalarAsync();
                    oldClientClass = resClass == null || resClass == DBNull.Value ? null : (string)resClass;
                }

                // 2. Si el dhcp4_client_class cambia, verificar si hay clientes activos en admin.servicios_clientes vinculados a este paquete
                if (oldClientClass != dto.Dhcp4ClientClass)
                {
                    int activeClientsCount = 0;
                    await using (var cmdCountClients = _dataSource.CreateCommand(@"
                        SELECT COUNT(*)::int FROM admin.servicios_clientes WHERE id_paquete = $1;"))
                    {
                        cmdCountClients.Parameters.AddWithValue(id);
                        activeClientsCount = (int)(await cmdCountClients.ExecuteScalarAsync() ?? 0);
                    }

                    if (activeClientsCount > 0)
                    {
                        return BadRequest(new { Error = $"No se puede modificar el Grupo de Pools de este Plan Comercial de '{oldClientClass ?? "Sin Grupo"}' a '{dto.Dhcp4ClientClass ?? "Sin Grupo"}' porque hay {activeClientsCount} clientes activos asignados a este plan. Cambiar el grupo dejará a estos usuarios sin asignación de IP DHCP." });
                    }
                }

                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.paquetes 
                    SET nombre = $1, velocidad_bajada_kbps = $2, velocidad_subida_kbps = $3, 
                        bootfile = $4, dhcp4_client_class = $5
                    WHERE id = $6
                    RETURNING id;");
                cmd.Parameters.AddWithValue(dto.Nombre.Trim());
                cmd.Parameters.AddWithValue(dto.VelocidadBajadaKbps);
                cmd.Parameters.AddWithValue(dto.VelocidadSubidaKbps);
                cmd.Parameters.AddWithValue((object?)dto.Bootfile ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)dto.Dhcp4ClientClass ?? DBNull.Value);
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null) return NotFound(new { Error = "El plan de velocidad solicitado no existe." });
                return Ok(new { Id = id, Message = "Plan de internet comercial actualizado con éxito." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al actualizar plan de velocidad: {ex.Message}" });
            }
        }

        // =========================================================================
        // --- SDN: AUTOMATIZACION Y RECARGA EN CALIENTE DE KEA ---
        // =========================================================================
        public static async Task SyncKeaConfigAsync(NpgsqlDataSource dataSource)
        {
            string configPath = "/app/kea/kea-dhcp4.conf";
            string tempPath = "/app/kea/kea-dhcp4.conf.tmp";

            if (!System.IO.File.Exists(configPath))
            {
                // Fallback de desarrollo para pruebas locales
                configPath = "../kea/kea-dhcp4.conf";
                tempPath = "../kea/kea-dhcp4.conf.tmp";
            }

            if (!System.IO.File.Exists(configPath))
            {
                Console.WriteLine($"[SDN WARNING] Archivo kea-dhcp4.conf no encontrado en {configPath}. Sincronización omitida.");
                return;
            }

            try
            {
                // 1. Leer y parsear el archivo existente para preservar configuraciones globales
                var configText = await System.IO.File.ReadAllTextAsync(configPath);
                
                var parseOptions = new System.Text.Json.JsonDocumentOptions
                {
                    CommentHandling = System.Text.Json.JsonCommentHandling.Skip,
                    AllowTrailingCommas = true
                };

                var configNode = System.Text.Json.Nodes.JsonNode.Parse(configText, null, parseOptions);
                if (configNode == null || configNode["Dhcp4"] == null)
                {
                    throw new Exception("El archivo kea-dhcp4.conf no tiene un formato válido (falta el nodo 'Dhcp4').");
                }

                // 2. Consultar subredes, pools y clases de cliente de la base de datos (con casteo seguro a texto)
                var globalSubnets = new System.Text.Json.Nodes.JsonArray();
                var sharedNetworksArray = new System.Text.Json.Nodes.JsonArray();
                var clientClassesArray = new System.Text.Json.Nodes.JsonArray();

                // Siempre agregar la clase base para cablemódems
                clientClassesArray.Add(new System.Text.Json.Nodes.JsonObject
                {
                    ["name"] = "docsis_modems",
                    ["test"] = "substring(option[60].hex, 0, 6) == 0x646f63736973 or substring(option[60].hex, 0, 6) == 0x444f43534953"
                });

                int leaseTimeSeconds = 86400;

                await using (var connection = await dataSource.OpenConnectionAsync())
                {
                    // Cargar el tiempo de arrendamiento DHCP global desde la base de datos (V1.7)
                    await using (var cmdLease = new Npgsql.NpgsqlCommand(@"
                        SELECT valor FROM admin.configuraciones WHERE clave = 'dhcp_lease_time';", connection))
                    {
                        var leaseVal = await cmdLease.ExecuteScalarAsync();
                        if (leaseVal != null && int.TryParse(leaseVal.ToString(), out int parsedLease))
                        {
                            leaseTimeSeconds = parsedLease;
                        }
                    }

                    // Cargar clases de cliente dinámicas de los planes de velocidad comerciales
                    var activeClientClasses = new List<string>();
                    await using (var cmdClasses = new Npgsql.NpgsqlCommand(@"
                        SELECT DISTINCT dhcp4_client_class
                        FROM admin.paquetes
                        WHERE dhcp4_client_class IS NOT NULL AND dhcp4_client_class <> ''
                        ORDER BY dhcp4_client_class;", connection))
                    {
                        await using (var readerClasses = await cmdClasses.ExecuteReaderAsync())
                        {
                            while (await readerClasses.ReadAsync())
                            {
                                activeClientClasses.Add(readerClasses.GetString(0));
                            }
                        }
                    }

                    foreach (var className in activeClientClasses)
                    {
                        if (className.Equals("docsis_modems", StringComparison.OrdinalIgnoreCase)) continue;

                        var classObj = new System.Text.Json.Nodes.JsonObject
                        {
                            ["name"] = className
                        };

                        if (className.Equals("dhcp-cpe-nat", StringComparison.OrdinalIgnoreCase))
                        {
                            classObj["test"] = "member('KNOWN') and not member('docsis_modems')";
                        }

                        clientClassesArray.Add(classObj);
                    }

                    // Cargar subredes físicas con información de su CMTS
                    await using (var cmdSubredes = new Npgsql.NpgsqlCommand(@"
                        SELECT s.id, s.cidr::text, s.gateway::text, s.tipo, s.nombre, s.id_cmts, c.nombre AS cmts_nombre
                        FROM admin.subredes s
                        JOIN admin.cmts c ON s.id_cmts = c.id
                        ORDER BY s.id;", connection))
                    {
                        await using (var readerSubredes = await cmdSubredes.ExecuteReaderAsync())
                        {
                            var subredes = new List<(int Id, string Cidr, string Gateway, string Tipo, string Nombre, int IdCmts, string CmtsNombre)>();
                            while (await readerSubredes.ReadAsync())
                            {
                                subredes.Add((
                                    readerSubredes.GetInt32(0),
                                    readerSubredes.GetString(1),
                                    readerSubredes.GetString(2),
                                    readerSubredes.GetString(3),
                                    readerSubredes.GetString(4),
                                    readerSubredes.GetInt32(5),
                                    readerSubredes.GetString(6)
                                ));
                            }
                            readerSubredes.Close();

                            var cpeGroups = new Dictionary<int, (string CmtsNombre, List<System.Text.Json.Nodes.JsonObject> Subnets)>();

                            foreach (var sub in subredes)
                            {
                                var subnetObj = new System.Text.Json.Nodes.JsonObject
                                {
                                    ["id"] = sub.Id,
                                    ["subnet"] = sub.Cidr
                                };

                                 // Cargar los pools asociados a esta subred
                                 var poolsArray = new System.Text.Json.Nodes.JsonArray();
                                 await using (var cmdPools = new Npgsql.NpgsqlCommand(@"
                                     SELECT p.rango_inicio::text, p.rango_fin::text, p.client_class
                                     FROM admin.pools p
                                     WHERE p.id_subred = $1 AND COALESCE(p.es_estatico, FALSE) = FALSE
                                     ORDER BY p.id;", connection))
                                {
                                    cmdPools.Parameters.AddWithValue(sub.Id);
                                    await using (var readerPools = await cmdPools.ExecuteReaderAsync())
                                    {
                                        while (await readerPools.ReadAsync())
                                        {
                                            string rawStart = readerPools.GetString(0);
                                            string rawEnd = readerPools.GetString(1);
                                            string cleanStart = rawStart.Replace("/32", "");
                                            string cleanEnd = rawEnd.Replace("/32", "");

                                            var poolObj = new System.Text.Json.Nodes.JsonObject
                                            {
                                                ["pool"] = $"{cleanStart} - {cleanEnd}"
                                            };

                                            if (!await readerPools.IsDBNullAsync(2))
                                            {
                                                string clientClass = readerPools.GetString(2);
                                                if (!string.IsNullOrWhiteSpace(clientClass))
                                                {
                                                    poolObj["client-class"] = clientClass;
                                                }
                                            }
                                            poolsArray.Add(poolObj);
                                        }
                                    }
                                }

                                subnetObj["pools"] = poolsArray;

                                // Cargar opciones de la subred (routers/gateway sin máscara /32 de host)
                                string cleanGateway = sub.Gateway.Replace("/32", "");
                                var optionArray = new System.Text.Json.Nodes.JsonArray
                                {
                                    new System.Text.Json.Nodes.JsonObject
                                    {
                                        ["name"] = "routers",
                                        ["data"] = cleanGateway
                                    }
                                };

                                // Si la subred es de tipo 'CM' (Gestión de Cablemódems), inyectamos automáticamente las opciones de infraestructura TFTP y ToD
                                if (sub.Tipo.Equals("CM", StringComparison.OrdinalIgnoreCase))
                                {
                                    string infraServerIp = Environment.GetEnvironmentVariable("INFRA_SERVER_IP") ?? "192.168.2.106";
                                    subnetObj["next-server"] = infraServerIp;
                                    subnetObj["server-hostname"] = infraServerIp;

                                    optionArray.Add(new System.Text.Json.Nodes.JsonObject
                                    {
                                        ["name"] = "time-servers",
                                        ["data"] = infraServerIp,
                                        ["always-send"] = true
                                    });
                                    optionArray.Add(new System.Text.Json.Nodes.JsonObject
                                    {
                                        ["name"] = "time-offset",
                                        ["data"] = "-10800",
                                        ["always-send"] = true
                                    });
                                    optionArray.Add(new System.Text.Json.Nodes.JsonObject
                                    {
                                        ["name"] = "log-servers",
                                        ["data"] = "0.0.0.0",
                                        ["always-send"] = true
                                    });
                                }

                                subnetObj["option-data"] = optionArray;

                                if (sub.Tipo.Equals("CM", StringComparison.OrdinalIgnoreCase))
                                {
                                    globalSubnets.Add(subnetObj);
                                }
                                else // tipo == "CPE"
                                {
                                    if (!cpeGroups.ContainsKey(sub.IdCmts))
                                    {
                                        cpeGroups[sub.IdCmts] = (sub.CmtsNombre, new List<System.Text.Json.Nodes.JsonObject>());
                                    }
                                    cpeGroups[sub.IdCmts].Subnets.Add(subnetObj);
                                }
                            }

                            // Agrupar en shared-networks solo si hay más de una subred CPE en un mismo CMTS
                            foreach (var group in cpeGroups)
                            {
                                if (group.Value.Subnets.Count > 1)
                                {
                                    var sharedObj = new System.Text.Json.Nodes.JsonObject
                                    {
                                        ["name"] = $"shared-{group.Value.CmtsNombre.ToLower().Replace(" ", "-")}",
                                        ["subnet4"] = new System.Text.Json.Nodes.JsonArray()
                                    };
                                    foreach (var sObj in group.Value.Subnets)
                                    {
                                        sharedObj["subnet4"]!.AsArray().Add(sObj);
                                    }
                                    sharedNetworksArray.Add(sharedObj);
                                }
                                else if (group.Value.Subnets.Count == 1)
                                {
                                    // Si hay una sola subred CPE para el CMTS, la dejamos plana en subnet4
                                    globalSubnets.Add(group.Value.Subnets[0]);
                                }
                            }
                        }
                    }
                }

                // 3. Reemplazar la sección 'subnet4', 'shared-networks' y 'client-classes' en el objeto JSON de Kea
                configNode["Dhcp4"]!["subnet4"] = globalSubnets;
                configNode["Dhcp4"]!["shared-networks"] = sharedNetworksArray;
                configNode["Dhcp4"]!["client-classes"] = clientClassesArray;

                // Inyectar el tiempo de arrendamiento DHCP global dinámico (V1.7)
                configNode["Dhcp4"]!["valid-lifetime"] = leaseTimeSeconds;
                configNode["Dhcp4"]!["renew-timer"] = leaseTimeSeconds / 2;
                configNode["Dhcp4"]!["rebind-timer"] = (int)(leaseTimeSeconds * 0.875);

                // Forzar que Kea busque reservas por dirección MAC física (HW-Address) y por Flexible Identifier (Option 82 Remote-ID)
                var identifiersArray = new System.Text.Json.Nodes.JsonArray { "hw-address", "flex-id" };
                configNode["Dhcp4"]!["host-reservation-identifiers"] = identifiersArray;
                configNode["Dhcp4"]!["store-extended-info"] = true;

                // Copia de seguridad por si falla la recarga caliente de Kea
                string backupPath = configPath + ".bak";
                if (System.IO.File.Exists(configPath))
                {
                    System.IO.File.Copy(configPath, backupPath, overwrite: true);
                }

                // 4. Guardar archivo de forma atómica para evitar colisiones de lectura (Race Conditions)
                var options = new System.Text.Json.JsonSerializerOptions 
                { 
                    WriteIndented = true,
                    Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                    TypeInfoResolver = System.Text.Json.JsonSerializerOptions.Default.TypeInfoResolver
                };
                var updatedConfigText = System.Text.Json.JsonSerializer.Serialize(configNode, options);

                await System.IO.File.WriteAllTextAsync(tempPath, updatedConfigText);
                System.IO.File.Move(tempPath, configPath, overwrite: true);
                Console.WriteLine("[SDN SUCCESS] Archivo kea-dhcp4.conf regenerado de forma atómica.");

                // 5. Llamada REST de recarga en caliente (Config Reload) a kea-ctrl-agent en el puerto 8001
                using (var httpClient = new System.Net.Http.HttpClient())
                {
                    var payload = new
                    {
                        command = "config-reload",
                        service = new[] { "dhcp4" }
                    };
                    var content = new System.Net.Http.StringContent(
                        System.Text.Json.JsonSerializer.Serialize(payload),
                        System.Text.Encoding.UTF8
                    );
                    content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");

                    var response = await httpClient.PostAsync("http://127.0.0.1:8001/", content);
                    if (!response.IsSuccessStatusCode)
                    {
                        if (System.IO.File.Exists(backupPath))
                        {
                            System.IO.File.Copy(backupPath, configPath, overwrite: true);
                        }
                        throw new Exception($"El Agente de Control Kea no respondió correctamente (Código HTTP {response.StatusCode}). Se restauró la configuración anterior.");
                    }

                    var responseBody = await response.Content.ReadAsStringAsync();
                    Console.WriteLine($"[SDN INFO] Comando de recarga enviado. Respuesta cruda: {responseBody}");

                    using (var jsonDoc = System.Text.Json.JsonDocument.Parse(responseBody))
                    {
                        var root = jsonDoc.RootElement;
                        if (root.ValueKind == System.Text.Json.JsonValueKind.Array && root.GetArrayLength() > 0)
                        {
                            var firstResponse = root[0];
                            int resultCode = firstResponse.GetProperty("result").GetInt32();
                            string resultText = firstResponse.GetProperty("text").GetString() ?? "";

                            if (resultCode != 0)
                            {
                                // Restaurar backup si falla la recarga semántica de Kea
                                if (System.IO.File.Exists(backupPath))
                                {
                                    System.IO.File.Copy(backupPath, configPath, overwrite: true);
                                }
                                throw new Exception($"Kea rechazó la recarga de configuración: {resultText}. Se restauró la configuración anterior.");
                            }
                            else
                            {
                                Console.WriteLine($"[SDN SUCCESS] Kea recargó la configuración exitosamente: {resultText}");
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SDN EXCEPTION] Error crítico al sincronizar configuración con Kea: {ex.Message}");
                throw;
            }
        }
    }
}
