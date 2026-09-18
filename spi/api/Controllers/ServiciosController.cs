using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ServiciosController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;
        private readonly Services.RebootQueueService _rebootQueue;

        public ServiciosController(NpgsqlDataSource dataSource, Services.RebootQueueService rebootQueue)
        {
            _dataSource = dataSource;
            _rebootQueue = rebootQueue;
        }

        public class ServicioCreateDto
        {
            public int IdCliente { get; set; }
            public int IdEquipo { get; set; }
            public int IdPaquete { get; set; }
            public int? IdCmts { get; set; }
            public string? IpCm { get; set; }  // Opcional para administración del CM
            public string? IpCpe { get; set; } // Opcional para IP fija del router CPE
            public string? DireccionInstalacion { get; set; } // Dirección física específica para este servicio
            
            // Llaves de negocio naturales para integración directa por API
            public string? CodigoCliente { get; set; }
            public string? MacEquipo { get; set; }
        }

        // 0. LISTADO DE SUSCRIPCIONES (GET /api/servicios)
        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var list = new List<object>();
            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT 
                        s.id,
                        s.id_cliente AS idCliente,
                        c.razon_social AS cliente,
                        s.id_equipo AS idEquipo,
                        e.mac::text AS equipoMac,
                        s.id_paquete AS idPaquete,
                        p.nombre AS paquete,
                        s.id_cmts AS idCmts,
                        cm.nombre AS cmts,
                        s.ip_cm::text AS ipCm,
                        s.ip_cpe::text AS ipCpe,
                        s.estado,
                        s.fecha_alta AS fechaActivacion,
                        s.direccion_instalacion
                    FROM admin.servicios_clientes s
                    JOIN admin.clientes c ON s.id_cliente = c.id
                    JOIN admin.equipos e ON s.id_equipo = e.id
                    JOIN admin.paquetes p ON s.id_paquete = p.id
                    LEFT JOIN admin.cmts cm ON s.id_cmts = cm.id
                    ORDER BY s.id DESC;");

                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var id = reader.GetInt32(0);
                    var idCliente = reader.GetInt32(1);
                    var cliente = reader.GetString(2);
                    var idEquipo = reader.GetInt32(3);
                    var equipoMac = reader.GetString(4);
                    var idPaquete = reader.GetInt32(5);
                    var paquete = reader.GetString(6);
                    var idCmts = reader.IsDBNull(7) ? (int?)null : reader.GetInt32(7);
                    var cmts = reader.IsDBNull(8) ? "⏳ Autodetectando..." : reader.GetString(8);
                    var ipCm = reader.IsDBNull(9) ? null : reader.GetString(9);
                    var ipCpe = reader.IsDBNull(10) ? null : reader.GetString(10);
                    var estado = reader.GetString(11);
                    var fechaActivacion = reader.GetDateTime(12);
                    var direccionInstalacion = reader.IsDBNull(13) ? null : reader.GetString(13);

                    // Para el frontend, ipAsignada muestra la IP de navegación (CPE) fija si existe,
                    // de lo contrario cae al CM o a null (mostrando "Esperando Lease / DHCP..." en el UI)
                    var ipAsignada = ipCpe ?? ipCm ?? null;

                    list.Add(new
                    {
                        Id = id,
                        IdCliente = idCliente,
                        Cliente = cliente,
                        IdEquipo = idEquipo,
                        EquipoMac = equipoMac,
                        IdPaquete = idPaquete,
                        Paquete = paquete,
                        IdCmts = idCmts,
                        Cmts = cmts,
                        IpCm = ipCm,
                        IpCpe = ipCpe,
                        IpAsignada = ipAsignada,
                        Estado = estado,
                        FechaActivacion = fechaActivacion,
                        DireccionInstalacion = direccionInstalacion
                    });
                }
                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al listar suscripciones: {ex.Message}" });
            }
        }

        // GET /api/servicios/lookup?mac=...&codigo=...&fields=...
        [HttpGet("lookup")]
        public async Task<IActionResult> Lookup([FromQuery] string? mac, [FromQuery] string? codigo, [FromQuery] string? fields)
        {
            if (string.IsNullOrWhiteSpace(mac) && string.IsNullOrWhiteSpace(codigo))
            {
                return BadRequest(new { Error = "Debe proveer al menos un parámetro de búsqueda: 'mac' o 'codigo' (Código de Facturación/Abonado)." });
            }

            if (!string.IsNullOrEmpty(mac))
            {
                // Formatear inteligentemente la MAC a formato estándar de Postgres: aa:bb:cc:dd:ee:ff
                var cleanMac = mac.Replace(":", "").Replace("-", "").Replace(".", "").Trim().ToLower();
                if (cleanMac.Length == 12)
                {
                    mac = $"{cleanMac[0..2]}:{cleanMac[2..4]}:{cleanMac[4..6]}:{cleanMac[6..8]}:{cleanMac[8..10]}:{cleanMac[10..12]}";
                }
                else
                {
                    return BadRequest(new { Error = "El formato de dirección MAC provisto no es válido. Debe tener 12 dígitos hexadecimales." });
                }
            }

            try
            {
                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT 
                        s.id,
                        s.estado,
                        s.fecha_alta,
                        s.ip_cm::text,
                        s.ip_cpe::text,
                        s.direccion_instalacion,
                        c.id AS clientId,
                        c.codigo AS clientCodigo,
                        c.razon_social AS clientRazonSocial,
                        c.cuit_dni AS clientCuitDni,
                        c.telefono AS clientTelefono,
                        c.email AS clientEmail,
                        c.direccion AS clientDireccionFiscal,
                        e.id AS equipoId,
                        e.mac::text AS equipoMac,
                        m.nombre AS equipoModelo,
                        cm.nombre AS cmtsNombre,
                        p.id AS paqueteId,
                        p.nombre AS paqueteNombre,
                        p.velocidad_bajada_kbps,
                        p.velocidad_subida_kbps
                    FROM admin.servicios_clientes s
                    JOIN admin.clientes c ON s.id_cliente = c.id
                    JOIN admin.equipos e ON s.id_equipo = e.id
                    JOIN admin.modelos m ON e.id_modelo = m.id
                    LEFT JOIN admin.cmts cm ON s.id_cmts = cm.id
                    JOIN admin.paquetes p ON s.id_paquete = p.id
                    WHERE ($1::text IS NOT NULL AND e.mac = $1::macaddr)
                       OR ($2::text IS NOT NULL AND LOWER(c.codigo) = LOWER($2::text))
                    LIMIT 1;");

                cmd.Parameters.AddWithValue((object?)mac ?? DBNull.Value);
                cmd.Parameters.AddWithValue((object?)codigo ?? DBNull.Value);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                {
                    var id = reader.GetInt32(0);
                    var estado = reader.GetString(1);
                    var fechaAlta = reader.GetDateTime(2);
                    var ipCm = reader.IsDBNull(3) ? null : reader.GetString(3);
                    var ipCpe = reader.IsDBNull(4) ? null : reader.GetString(4);
                    var direccionInstalacion = reader.IsDBNull(5) ? null : reader.GetString(5);

                    var clientId = reader.GetInt32(6);
                    var clientCodigo = reader.IsDBNull(7) ? null : reader.GetString(7);
                    var clientRazonSocial = reader.GetString(8);
                    var clientCuitDni = reader.GetString(9);
                    var clientTelefono = reader.IsDBNull(10) ? null : reader.GetString(10);
                    var clientEmail = reader.IsDBNull(11) ? null : reader.GetString(11);
                    var clientDireccionFiscal = reader.IsDBNull(12) ? null : reader.GetString(12);

                    var equipoId = reader.GetInt32(13);
                    var equipoMac = reader.GetString(14);
                    var equipoModelo = reader.GetString(15);
                    var cmtsNombre = reader.IsDBNull(16) ? "⏳ Autodetectando..." : reader.GetString(16);

                    var paqueteId = reader.GetInt32(17);
                    var paqueteNombre = reader.GetString(18);
                    var velocidadDown = reader.GetInt32(19);
                    var velocidadUp = reader.GetInt32(20);

                    await reader.CloseAsync();

                    // Si las IPs son dinámicas, intentar recuperarlas de los leases activos de Kea en tiempo real
                    bool esIpFija = !string.IsNullOrEmpty(ipCpe);
                    if (string.IsNullOrEmpty(ipCm))
                    {
                        try
                        {
                            await using var cmdLease = _dataSource.CreateCommand();
                            cmdLease.CommandText = @"
                                SELECT ('0.0.0.0'::inet + address)::text 
                                FROM public.lease4 
                                WHERE hwaddr = DECODE(REPLACE($1::text, ':', ''), 'hex')
                                LIMIT 1;";
                            cmdLease.Parameters.AddWithValue(equipoMac);
                            ipCm = (string?)await cmdLease.ExecuteScalarAsync();
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine($"[DIAGNOSTICS ERROR] No se pudo recuperar IP dinámica CM: {ex.Message}");
                        }
                    }

                    if (string.IsNullOrEmpty(ipCpe))
                    {
                        try
                        {
                            await using var cmdLease = _dataSource.CreateCommand();
                            cmdLease.CommandText = @"
                                SELECT ('0.0.0.0'::inet + address)::text 
                                FROM public.lease4 
                                WHERE remote_id = DECODE(REPLACE($1::text, ':', ''), 'hex')
                                  AND hwaddr != DECODE(REPLACE($1::text, ':', ''), 'hex')
                                LIMIT 1;";
                            cmdLease.Parameters.AddWithValue(equipoMac);
                            ipCpe = (string?)await cmdLease.ExecuteScalarAsync();
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine($"[DIAGNOSTICS ERROR] No se pudo recuperar IP dinámica CPE: {ex.Message}");
                        }
                    }

                    var response = new
                    {
                        ServicioId = id,
                        Estado = estado,
                        FechaActivacion = fechaAlta,
                        Cliente = new
                        {
                            Id = clientId,
                            CodigoFacturacion = clientCodigo,
                            RazonSocial = clientRazonSocial,
                            CuitDni = clientCuitDni,
                            Telefono = clientTelefono,
                            Email = clientEmail,
                            DireccionFiscal = clientDireccionFiscal
                        },
                        Instalacion = new
                        {
                            Direccion = direccionInstalacion ?? clientDireccionFiscal,
                            EsDireccionEspecifica = !string.IsNullOrEmpty(direccionInstalacion)
                        },
                        Equipamiento = new
                        {
                            Id = equipoId,
                            Mac = equipoMac,
                            Modelo = equipoModelo,
                            NodoCmts = cmtsNombre
                        },
                        Ips = new
                        {
                            IpCm = ipCm,
                            IpCpe = ipCpe,
                            EsIpFija = esIpFija
                        },
                        Plan = new
                        {
                            Id = paqueteId,
                            Nombre = paqueteNombre,
                            VelocidadBajadaKbps = velocidadDown,
                            VelocidadSubidaKbps = velocidadUp
                        }
                    };

                    return Ok(ProjectFields(response, fields));
                }

                return NotFound(new { Message = "No se encontró ningún servicio activo para el abonado con los filtros provistos." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al buscar servicio: {ex.Message}" });
            }
        }

        // GET /api/servicios/search?query=...&fields=...
        [HttpGet("search")]
        public async Task<IActionResult> Search([FromQuery] string query, [FromQuery] string? fields)
        {
            if (string.IsNullOrWhiteSpace(query))
            {
                return BadRequest(new { Error = "Debe proveer un término de búsqueda en el parámetro 'query'." });
            }

            var wildcardQuery = $"%{query.Trim()}%";

            try
            {
                var list = new List<object>();

                await using var cmd = _dataSource.CreateCommand(@"
                    SELECT DISTINCT
                        s.id,
                        s.estado,
                        s.fecha_alta,
                        s.ip_cm::text,
                        s.ip_cpe::text,
                        s.direccion_instalacion,
                        c.id AS clientId,
                        c.codigo AS clientCodigo,
                        c.razon_social AS clientRazonSocial,
                        c.cuit_dni AS clientCuitDni,
                        c.telefono AS clientTelefono,
                        c.email AS clientEmail,
                        c.direccion AS clientDireccionFiscal,
                        e.id AS equipoId,
                        e.mac::text AS equipoMac,
                        m.nombre AS equipoModelo,
                        cm.nombre AS cmtsNombre,
                        p.id AS paqueteId,
                        p.nombre AS paqueteNombre,
                        p.velocidad_bajada_kbps,
                        p.velocidad_subida_kbps
                    FROM admin.servicios_clientes s
                    JOIN admin.clientes c ON s.id_cliente = c.id
                    JOIN admin.equipos e ON s.id_equipo = e.id
                    JOIN admin.modelos m ON e.id_modelo = m.id
                    LEFT JOIN admin.cmts cm ON s.id_cmts = cm.id
                    JOIN admin.paquetes p ON s.id_paquete = p.id
                    WHERE c.razon_social ILIKE $1
                       OR c.direccion ILIKE $1
                       OR s.direccion_instalacion ILIKE $1
                       OR c.codigo ILIKE $1
                       OR e.mac::text ILIKE $1
                       OR s.ip_cm::text ILIKE $1
                       OR s.ip_cpe::text ILIKE $1
                    ORDER BY s.id DESC
                    LIMIT 100;");

                cmd.Parameters.AddWithValue(wildcardQuery);

                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    var id = reader.GetInt32(0);
                    var estado = reader.GetString(1);
                    var fechaAlta = reader.GetDateTime(2);
                    var ipCm = reader.IsDBNull(3) ? null : reader.GetString(3);
                    var ipCpe = reader.IsDBNull(4) ? null : reader.GetString(4);
                    var direccionInstalacion = reader.IsDBNull(5) ? null : reader.GetString(5);

                    var clientId = reader.GetInt32(6);
                    var clientCodigo = reader.IsDBNull(7) ? null : reader.GetString(7);
                    var clientRazonSocial = reader.GetString(8);
                    var clientCuitDni = reader.GetString(9);
                    var clientTelefono = reader.IsDBNull(10) ? null : reader.GetString(10);
                    var clientEmail = reader.IsDBNull(11) ? null : reader.GetString(11);
                    var clientDireccionFiscal = reader.IsDBNull(12) ? null : reader.GetString(12);

                    var equipoId = reader.GetInt32(13);
                    var equipoMac = reader.GetString(14);
                    var equipoModelo = reader.GetString(15);
                    var cmtsNombre = reader.IsDBNull(16) ? "⏳ Autodetectando..." : reader.GetString(16);

                    var paqueteId = reader.GetInt32(17);
                    var paqueteNombre = reader.GetString(18);
                    var velocidadDown = reader.GetInt32(19);
                    var velocidadUp = reader.GetInt32(20);

                    var fullItem = new
                    {
                        ServicioId = id,
                        Estado = estado,
                        FechaActivacion = fechaAlta,
                        Cliente = new
                        {
                            Id = clientId,
                            CodigoFacturacion = clientCodigo,
                            RazonSocial = clientRazonSocial,
                            CuitDni = clientCuitDni,
                            Telefono = clientTelefono,
                            Email = clientEmail,
                            DireccionFiscal = clientDireccionFiscal
                        },
                        Instalacion = new
                        {
                            Direccion = direccionInstalacion ?? clientDireccionFiscal,
                            EsDireccionEspecifica = !string.IsNullOrEmpty(direccionInstalacion)
                        },
                        Equipamiento = new
                        {
                            Id = equipoId,
                            Mac = equipoMac,
                            Modelo = equipoModelo,
                            NodoCmts = cmtsNombre
                        },
                        Ips = new
                        {
                            IpCm = ipCm,
                            IpCpe = ipCpe,
                            EsIpFija = !string.IsNullOrEmpty(ipCpe)
                        },
                        Plan = new
                        {
                            Id = paqueteId,
                            Nombre = paqueteNombre,
                            VelocidadBajadaKbps = velocidadDown,
                            VelocidadSubidaKbps = velocidadUp
                        }
                    };

                    list.Add(ProjectFields(fullItem, fields));
                }

                return Ok(list);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error en la búsqueda permisiva: {ex.Message}" });
            }
        }

        private object ProjectFields(object fullObject, string? fields)
        {
            if (string.IsNullOrWhiteSpace(fields))
            {
                return fullObject;
            }

            var allowedFields = fields.Split(',', StringSplitOptions.RemoveEmptyEntries)
                                      .Select(f => f.Trim().ToLower())
                                      .ToHashSet();

            var fullDict = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(
                System.Text.Json.JsonSerializer.Serialize(fullObject)
            );

            if (fullDict == null) return fullObject;

            var projectedDict = new Dictionary<string, object>();

            // Siempre retornar los campos identificadores base/metadata para trazabilidad
            if (fullDict.ContainsKey("servicioId")) projectedDict["servicioId"] = fullDict["servicioId"];
            if (fullDict.ContainsKey("estado")) projectedDict["estado"] = fullDict["estado"];
            if (fullDict.ContainsKey("fechaActivacion")) projectedDict["fechaActivacion"] = fullDict["fechaActivacion"];

            // Proyectar dinámicamente las secciones solicitadas
            foreach (var field in allowedFields)
            {
                switch (field)
                {
                    case "cliente":
                        if (fullDict.ContainsKey("cliente")) projectedDict["cliente"] = fullDict["cliente"];
                        break;
                    case "instalacion":
                        if (fullDict.ContainsKey("instalacion")) projectedDict["instalacion"] = fullDict["instalacion"];
                        break;
                    case "equipamiento":
                        if (fullDict.ContainsKey("equipamiento")) projectedDict["equipamiento"] = fullDict["equipamiento"];
                        break;
                    case "ips":
                        if (fullDict.ContainsKey("ips")) projectedDict["ips"] = fullDict["ips"];
                        break;
                    case "plan":
                        if (fullDict.ContainsKey("plan")) projectedDict["plan"] = fullDict["plan"];
                        break;
                }
            }

            return projectedDict;
        }

        // 1. ALTA DE SERVICIO COMERCIAL Y TÉCNICO (POST /api/servicios)
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] ServicioCreateDto dto)
        {
            await using var connection = await _dataSource.OpenConnectionAsync();
            await using var transaction = await connection.BeginTransactionAsync();
            await SetSessionOperatorAsync(connection, transaction);

            try
            {
                // Forzar que todo servicio nuevo nazca en modo Autodetección (id_cmts = NULL, IPs = NULL)
                dto.IdCmts = null;
                dto.IpCm = null;
                dto.IpCpe = null;

                // Auto-resolver Cliente si se provee CodigoCliente
                if (dto.IdCliente <= 0 && !string.IsNullOrEmpty(dto.CodigoCliente))
                {
                    await using var cmdCl = new NpgsqlCommand("SELECT id FROM admin.clientes WHERE codigo = $1;", connection, transaction);
                    cmdCl.Parameters.AddWithValue(dto.CodigoCliente.Trim());
                    var resCl = await cmdCl.ExecuteScalarAsync();
                    if (resCl == null)
                    {
                        return NotFound(new { Error = $"El cliente con código de facturación '{dto.CodigoCliente}' no existe en la plataforma." });
                    }
                    dto.IdCliente = Convert.ToInt32(resCl);
                }

                // Auto-resolver Equipo si se provee MacEquipo
                if (dto.IdEquipo <= 0 && !string.IsNullOrEmpty(dto.MacEquipo))
                {
                    // Normalizar MAC
                    var cleanMac = dto.MacEquipo.Replace(":", "").Replace("-", "").Replace(".", "").Trim().ToLower();
                    if (cleanMac.Length == 12)
                    {
                        var normMac = $"{cleanMac[0..2]}:{cleanMac[2..4]}:{cleanMac[4..6]}:{cleanMac[6..8]}:{cleanMac[8..10]}:{cleanMac[10..12]}";
                        await using var cmdEq = new NpgsqlCommand("SELECT id FROM admin.equipos WHERE mac = $1::macaddr;", connection, transaction);
                        cmdEq.Parameters.AddWithValue(normMac);
                        var resEq = await cmdEq.ExecuteScalarAsync();
                        if (resEq == null)
                        {
                            return NotFound(new { Error = $"El equipo físico con dirección MAC '{dto.MacEquipo}' no existe en el inventario." });
                        }
                        dto.IdEquipo = Convert.ToInt32(resEq);
                    }
                    else
                    {
                        return BadRequest(new { Error = "Formato de dirección MAC del equipo inválido en el alta simplificada." });
                    }
                }

                if (dto.IdCliente <= 0 || dto.IdEquipo <= 0)
                {
                    return BadRequest(new { Error = "Debe proveer un cliente y un equipo válidos (ya sea por ID numérico o por sus llaves de negocio únicas)." });
                }

                // A. Validar que el equipo físico esté en stock ('INVENTARIO')
                await using (var cmdCheckStock = new NpgsqlCommand("SELECT estado, mac::text FROM admin.equipos WHERE id = $1;", connection, transaction))
                {
                    cmdCheckStock.Parameters.AddWithValue(dto.IdEquipo);
                    await using var reader = await cmdCheckStock.ExecuteReaderAsync();
                    if (!await reader.ReadAsync())
                    {
                        return NotFound(new { Error = $"El equipo físico con ID {dto.IdEquipo} no existe en la base de datos" });
                    }
                    var estadoStock = reader.GetString(0);
                    var macEquipo = reader.GetString(1);
                    if (estadoStock != "INVENTARIO")
                    {
                        return BadRequest(new { Error = $"El equipo con MAC {macEquipo} no está disponible en inventario. Estado actual: {estadoStock}" });
                    }
                }

                // E. Guardar la Suscripción Comercial como ACTIVO (con CMTS e IPs en NULL de forma inicial)
                // ¡El trigger trg_sync_servicio_to_kea_hosts() se disparará al insertar y sincronizará a Kea DHCP!
                int nuevoServicioId;
                await using (var cmdInsert = new NpgsqlCommand(@"
                    INSERT INTO admin.servicios_clientes (id_cliente, id_equipo, id_paquete, id_cmts, ip_cm, ip_cpe, estado, direccion_instalacion)
                    VALUES ($1, $2, $3, $4, $5::inet, $6::inet, 'ACTIVO', $7)
                    RETURNING id;", connection, transaction))
                {
                    cmdInsert.Parameters.AddWithValue(dto.IdCliente);
                    cmdInsert.Parameters.AddWithValue(dto.IdEquipo);
                    cmdInsert.Parameters.AddWithValue(dto.IdPaquete);
                    cmdInsert.Parameters.AddWithValue((object?)dto.IdCmts ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue((object?)dto.IpCm ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue((object?)dto.IpCpe ?? DBNull.Value);
                    cmdInsert.Parameters.AddWithValue((object?)dto.DireccionInstalacion ?? DBNull.Value);

                    nuevoServicioId = Convert.ToInt32(await cmdInsert.ExecuteScalarAsync());
                }

                await transaction.CommitAsync();

                return StatusCode(201, new
                {
                    Id = nuevoServicioId,
                    Estado = "ACTIVO",
                    Message = "Suscripción activada comercialmente e inyectada en Kea DHCP de forma automática"
                });
            }
            catch (Exception ex)
            {
                await transaction.RollbackAsync();
                return BadRequest(new { Error = $"Transacción abortada: {ex.Message}" });
            }
        }

        // 1.1 MODIFICACIÓN DE SERVICIO COMERCIAL Y TÉCNICO (PUT /api/servicios/{id})
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] ServicioCreateDto dto)
        {
            await using var connection = await _dataSource.OpenConnectionAsync();
            await using var transaction = await connection.BeginTransactionAsync();
            await SetSessionOperatorAsync(connection, transaction);

            try
            {
                // A. Obtener datos actuales del servicio para comparar equipo e identificar relocalización/reemplazo
                int idEquipoAnterior = 0;
                int? idCmtsAnterior = null;
                string? ipCmAnterior = null;
                string? ipCpeAnterior = null;
                string? rebootIp = null;
                string? rebootMac = null;

                await using (var cmdGetOld = new NpgsqlCommand("SELECT id_equipo, id_cmts, ip_cm::text, ip_cpe::text FROM admin.servicios_clientes WHERE id = $1;", connection, transaction))
                {
                    cmdGetOld.Parameters.AddWithValue(id);
                    await using var readerOld = await cmdGetOld.ExecuteReaderAsync();
                    if (!await readerOld.ReadAsync())
                    {
                        return NotFound(new { Error = $"La suscripción con ID {id} no existe" });
                    }
                    idEquipoAnterior = readerOld.GetInt32(0);
                    idCmtsAnterior = readerOld.IsDBNull(1) ? (int?)null : readerOld.GetInt32(1);
                    ipCmAnterior = readerOld.IsDBNull(2) ? null : readerOld.GetString(2);
                    ipCpeAnterior = readerOld.IsDBNull(3) ? null : readerOld.GetString(3);
                }

                // Obtener IP y MAC activos de gestión antes de modificar nada para el posterior reinicio SNMP
                await using (var cmdGetActive = new NpgsqlCommand(@"
                    SELECT host(COALESCE(s.ip_cm, '0.0.0.0'::inet + l.address)) as ip, e.mac::text 
                    FROM admin.servicios_clientes s
                    JOIN admin.equipos e ON e.id = s.id_equipo
                    LEFT JOIN public.lease4 l ON l.hwaddr = decode(replace(e.mac::text, ':', ''), 'hex')
                    WHERE s.id = $1 AND (s.ip_cm IS NOT NULL OR l.address IS NOT NULL);", connection, transaction))
                {
                    cmdGetActive.Parameters.AddWithValue(id);
                    await using var readerActive = await cmdGetActive.ExecuteReaderAsync();
                    if (await readerActive.ReadAsync())
                    {
                        rebootIp = readerActive.GetString(0);
                        rebootMac = readerActive.GetString(1);
                    }
                }

                // B. Si cambió de equipo (Reemplazo de módem por falla / soporte), forzar desasignación de CMTS e IPs fijas
                if (dto.IdEquipo != idEquipoAnterior)
                {
                    // Validar que el nuevo equipo físico esté en stock ('INVENTARIO')
                    await using (var cmdCheckStock = new NpgsqlCommand("SELECT estado, mac::text FROM admin.equipos WHERE id = $1;", connection, transaction))
                    {
                        cmdCheckStock.Parameters.AddWithValue(dto.IdEquipo);
                        await using var reader = await cmdCheckStock.ExecuteReaderAsync();
                        if (!await reader.ReadAsync())
                        {
                            return NotFound(new { Error = $"El equipo físico con ID {dto.IdEquipo} no existe" });
                        }
                        var estadoStock = reader.GetString(0);
                        var macEquipo = reader.GetString(1);
                        if (estadoStock != "INVENTARIO")
                        {
                            return BadRequest(new { Error = $"El equipo con MAC {macEquipo} no está disponible en inventario (Estado actual: {estadoStock}). No se puede realizar el cambio de hardware." });
                        }
                    }

                    // Forzar que el nuevo módem se autodetecte en su primer ciclo de DHCP (Bypass)
                    dto.IdCmts = null;
                    dto.IpCm = null;
                    dto.IpCpe = null;
                }
                else
                {
                    // Al no modificar el hardware, como el formulario web no envía campos técnicos (CMTS ni IPs),
                    // resguardamos y mantenemos intactas las asignaciones previas existentes en la base de datos.
                    dto.IdCmts = idCmtsAnterior;
                    dto.IpCm = ipCmAnterior;
                    dto.IpCpe = ipCpeAnterior;
                }

                // C. Si el CMTS es válido y no nulo, procesamos IPAM de forma segura (para sistemas estáticos legacy)
                if (dto.IdCmts != null)
                {
                    // Resolver IPs fijas automáticas si se cambian a "AUTO"
                    bool isCmAuto = string.Equals(dto.IpCm, "AUTO", StringComparison.OrdinalIgnoreCase);
                    if (isCmAuto)
                    {
                        dto.IpCm = await ResolveAutoIpAsync(connection, transaction, dto.IdCmts.Value, "CM");
                    }

                    bool isCpeAuto = string.Equals(dto.IpCpe, "AUTO", StringComparison.OrdinalIgnoreCase);
                    if (isCpeAuto)
                    {
                        dto.IpCpe = await ResolveAutoIpAsync(connection, transaction, dto.IdCmts.Value, "CPE");
                    }

                    // Validar IP de Gestión del CM contra las subredes de CM de ese CMTS
                    if (!string.IsNullOrWhiteSpace(dto.IpCm))
                    {
                        await using var cmdCheckCmIp = new NpgsqlCommand(@"
                            SELECT id FROM admin.subredes 
                            WHERE id_cmts = $1 AND tipo = 'CM' AND $2::inet <<= cidr;", connection, transaction);
                        cmdCheckCmIp.Parameters.AddWithValue(dto.IdCmts);
                        cmdCheckCmIp.Parameters.AddWithValue(dto.IpCm);

                        var subredId = await cmdCheckCmIp.ExecuteScalarAsync();
                        if (subredId == null)
                        {
                            return BadRequest(new { Error = $"La IP de gestión CM '{dto.IpCm}' no pertenece a ninguna subred 'CM' habilitada en el CMTS asignado" });
                        }
                    }

                    // Validar IP de Navegación del CPE contra las subredes de CPE de ese CMTS
                    if (!string.IsNullOrWhiteSpace(dto.IpCpe))
                    {
                        await using var cmdCheckCpeIp = new NpgsqlCommand(@"
                            SELECT id FROM admin.subredes 
                            WHERE id_cmts = $1 AND tipo = 'CPE' AND $2::inet <<= cidr;", connection, transaction);
                        cmdCheckCpeIp.Parameters.AddWithValue(dto.IdCmts);
                        cmdCheckCpeIp.Parameters.AddWithValue(dto.IpCpe);

                        var subredId = await cmdCheckCpeIp.ExecuteScalarAsync();
                        if (subredId == null)
                        {
                            return BadRequest(new { Error = $"La IP de ruteo CPE fija '{dto.IpCpe}' no pertenece a ninguna subred 'CPE' habilitada en el CMTS asignado" });
                        }
                    }
                }

                // F. Actualizar la suscripción de forma segura en base de datos
                await using (var cmdUpdate = new NpgsqlCommand(@"
                    UPDATE admin.servicios_clientes 
                    SET id_cliente = $1, id_equipo = $2, id_paquete = $3, id_cmts = $4, ip_cm = $5::inet, ip_cpe = $6::inet, direccion_instalacion = $7, fecha_modificacion = NOW()
                    WHERE id = $8;", connection, transaction))
                {
                    cmdUpdate.Parameters.AddWithValue(dto.IdCliente);
                    cmdUpdate.Parameters.AddWithValue(dto.IdEquipo);
                    cmdUpdate.Parameters.AddWithValue(dto.IdPaquete);
                    cmdUpdate.Parameters.AddWithValue((object?)dto.IdCmts ?? DBNull.Value);
                    cmdUpdate.Parameters.AddWithValue((object?)dto.IpCm ?? DBNull.Value);
                    cmdUpdate.Parameters.AddWithValue((object?)dto.IpCpe ?? DBNull.Value);
                    cmdUpdate.Parameters.AddWithValue((object?)dto.DireccionInstalacion ?? DBNull.Value);
                    cmdUpdate.Parameters.AddWithValue(id);

                    await cmdUpdate.ExecuteNonQueryAsync();
                }

                // G. Limpiar cualquier reserva temporal para las IPs consumidas (si existieran)
                if (dto.IdCmts != null)
                {
                    await using (var cmdCleanReservas = new NpgsqlCommand(@"
                        DELETE FROM admin.ip_reservas_temporales 
                        WHERE ip = $1::inet OR ip = $2::inet;", connection, transaction))
                    {
                        cmdCleanReservas.Parameters.AddWithValue((object?)dto.IpCm ?? DBNull.Value);
                        cmdCleanReservas.Parameters.AddWithValue((object?)dto.IpCpe ?? DBNull.Value);
                        await cmdCleanReservas.ExecuteNonQueryAsync();
                    }
                }

                await transaction.CommitAsync();

                // F. Encolar reboot para el módem activo
                if (!string.IsNullOrEmpty(rebootIp) && !string.IsNullOrEmpty(rebootMac))
                {
                    _rebootQueue.EnqueueReboot(rebootIp, rebootMac);
                }

                return Ok(new
                {
                    Id = id,
                    Message = "Suscripción actualizada con éxito. Se ha re-aprovisionado el enlace y encolado el reinicio del módem."
                });
            }
            catch (Exception ex)
            {
                await transaction.RollbackAsync();
                return BadRequest(new { Error = $"Transacción de actualización abortada: {ex.Message}" });
            }
        }

        // 2. SUSPENSIÓN DE SERVICIO (PUT/POST /api/servicios/{id}/suspender)
        [HttpPut("{id}/suspender")]
        [HttpPost("{id}/suspender")]
        public async Task<IActionResult> Suspender(int id)
        {
            try
            {
                string? rebootIp = null;
                string? rebootMac = null;

                // Obtener IP y MAC activos de gestión antes de suspender para el posterior reinicio SNMP
                await using (var cmdGetActive = _dataSource.CreateCommand(@"
                    SELECT host(COALESCE(s.ip_cm, '0.0.0.0'::inet + l.address)) as ip, e.mac::text 
                    FROM admin.servicios_clientes s
                    JOIN admin.equipos e ON e.id = s.id_equipo
                    LEFT JOIN public.lease4 l ON l.hwaddr = decode(replace(e.mac::text, ':', ''), 'hex')
                    WHERE s.id = $1 AND (s.ip_cm IS NOT NULL OR l.address IS NOT NULL);"))
                {
                    cmdGetActive.Parameters.AddWithValue(id);
                    await using var readerActive = await cmdGetActive.ExecuteReaderAsync();
                    if (await readerActive.ReadAsync())
                    {
                        rebootIp = readerActive.GetString(0);
                        rebootMac = readerActive.GetString(1);
                    }
                }

                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.servicios_clientes 
                    SET estado = 'SUSPENDIDO', fecha_modificacion = NOW()
                    WHERE id = $1
                    RETURNING id;");
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null)
                {
                    return NotFound(new { Error = $"La suscripción con ID {id} no fue encontrada" });
                }

                if (!string.IsNullOrEmpty(rebootIp) && !string.IsNullOrEmpty(rebootMac))
                {
                    _rebootQueue.EnqueueReboot(rebootIp, rebootMac);
                }

                return Ok(new
                {
                    Id = id,
                    Estado = "SUSPENDIDO",
                    Message = "Suscripción suspendida. Las reservas en Kea DHCP han sido eliminadas automáticamente y se encoló el reinicio del módem."
                });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al suspender: {ex.Message}" });
            }
        }

        // 3. REACTIVACIÓN DE SERVICIO (PUT/POST /api/servicios/{id}/reactivar)
        [HttpPut("{id}/reactivar")]
        [HttpPost("{id}/reactivar")]
        public async Task<IActionResult> Reactivar(int id)
        {
            try
            {
                string? rebootIp = null;
                string? rebootMac = null;

                // Obtener IP y MAC activos antes de reactivar (antes de cualquier actualización)
                await using (var cmdGetActive = _dataSource.CreateCommand(@"
                    SELECT host(COALESCE(s.ip_cm, '0.0.0.0'::inet + l.address)) as ip, e.mac::text 
                    FROM admin.servicios_clientes s
                    JOIN admin.equipos e ON e.id = s.id_equipo
                    LEFT JOIN public.lease4 l ON l.hwaddr = decode(replace(e.mac::text, ':', ''), 'hex')
                    WHERE s.id = $1 AND (s.ip_cm IS NOT NULL OR l.address IS NOT NULL);"))
                {
                    cmdGetActive.Parameters.AddWithValue(id);
                    await using var readerActive = await cmdGetActive.ExecuteReaderAsync();
                    if (await readerActive.ReadAsync())
                    {
                        rebootIp = readerActive.GetString(0);
                        rebootMac = readerActive.GetString(1);
                    }
                }

                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.servicios_clientes 
                    SET estado = 'ACTIVO', fecha_modificacion = NOW()
                    WHERE id = $1
                    RETURNING id;");
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null)
                {
                    return NotFound(new { Error = $"La suscripción con ID {id} no fue encontrada" });
                }

                if (!string.IsNullOrEmpty(rebootIp) && !string.IsNullOrEmpty(rebootMac))
                {
                    _rebootQueue.EnqueueReboot(rebootIp, rebootMac);
                }

                return Ok(new
                {
                    Id = id,
                    Estado = "ACTIVO",
                    Message = "Suscripción reactivada con éxito. El Cablemódem y el CPE han sido re-aprovisionados en Kea DHCP y se encoló el reinicio del módem."
                });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al reactivar: {ex.Message}" });
            }
        }

        public class BulkEstadoDto
        {
            public List<int> Ids { get; set; } = null!;
            public string NuevoEstado { get; set; } = null!;
        }

        // 4. SUSPENSIÓN / REACTIVACIÓN MASIVA DE SERVICIOS (POST /api/servicios/bulk-estado)
        [HttpPost("bulk-estado")]
        public async Task<IActionResult> BulkEstado([FromBody] BulkEstadoDto dto)
        {
            if (dto.Ids == null || dto.Ids.Count == 0)
            {
                return BadRequest(new { Error = "Debe proveer una lista de IDs de servicio a modificar" });
            }

            if (dto.NuevoEstado != "ACTIVO" && dto.NuevoEstado != "SUSPENDIDO")
            {
                return BadRequest(new { Error = "Estado masivo inválido. Solo se permite ACTIVO o SUSPENDIDO" });
            }

            try
            {
                // A. Obtener IPs y MACs de gestión antes de actualizar (Soporta fallback por lease4)
                var rebootTargets = new List<(string Ip, string Mac)>();
                await using (var cmdGetActive = _dataSource.CreateCommand(@"
                    SELECT host(COALESCE(s.ip_cm, '0.0.0.0'::inet + l.address)) as ip, e.mac::text 
                    FROM admin.servicios_clientes s
                    JOIN admin.equipos e ON e.id = s.id_equipo
                    LEFT JOIN public.lease4 l ON l.hwaddr = decode(replace(e.mac::text, ':', ''), 'hex')
                    WHERE s.id = ANY($1) AND (s.ip_cm IS NOT NULL OR l.address IS NOT NULL);"))
                {
                    cmdGetActive.Parameters.AddWithValue(dto.Ids.ToArray());
                    await using var readerActive = await cmdGetActive.ExecuteReaderAsync();
                    while (await readerActive.ReadAsync())
                    {
                        rebootTargets.Add((readerActive.GetString(0), readerActive.GetString(1)));
                    }
                }

                // B. Un único UPDATE masivo utilizando el operador nativo ANY de Postgres
                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.servicios_clientes 
                    SET estado = $1, fecha_modificacion = NOW()
                    WHERE id = ANY($2)
                    RETURNING id;");

                cmd.Parameters.AddWithValue(dto.NuevoEstado);
                cmd.Parameters.AddWithValue(dto.Ids.ToArray());

                var affectedList = new List<int>();
                await using (var reader = await cmd.ExecuteReaderAsync())
                {
                    while (await reader.ReadAsync())
                    {
                        affectedList.Add(reader.GetInt32(0));
                    }
                }

                // C. Encolar reinicios masivos
                foreach (var target in rebootTargets)
                {
                    _rebootQueue.EnqueueReboot(target.Ip, target.Mac);
                }

                return Ok(new
                {
                    Procesados = affectedList.Count,
                    EstadoAplicado = dto.NuevoEstado,
                    Message = $"Se actualizaron {affectedList.Count} suscripciones comerciales y se inyectaron en la cola de reinicios masivos seguros."
                });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error en la transacción masiva: {ex.Message}" });
            }
        }

        public class BulkEstadoByCodigosDto
        {
            public List<string> Codigos { get; set; } = null!;
            public string NuevoEstado { get; set; } = null!;
        }

        // 4.1. SUSPENSIÓN / REACTIVACIÓN MASIVA DE SERVICIOS POR CÓDIGO DE FACTURACIÓN (POST /api/servicios/bulk-estado-by-codigos)
        [HttpPost("bulk-estado-by-codigos")]
        public async Task<IActionResult> BulkEstadoByCodigos([FromBody] BulkEstadoByCodigosDto dto)
        {
            if (dto.Codigos == null || dto.Codigos.Count == 0)
            {
                return BadRequest(new { Error = "Debe proveer una lista de códigos de facturación" });
            }

            if (dto.NuevoEstado != "ACTIVO" && dto.NuevoEstado != "SUSPENDIDO")
            {
                return BadRequest(new { Error = "Estado masivo inválido. Solo se permite ACTIVO o SUSPENDIDO" });
            }

            // Normalizar códigos (quitar vacíos, trim)
            var cleanCodigos = dto.Codigos.Select(c => c.Trim()).Where(c => !string.IsNullOrEmpty(c)).ToArray();
            if (cleanCodigos.Length == 0)
            {
                return BadRequest(new { Error = "La lista de códigos de facturación no es válida" });
            }

            try
            {
                // A. Obtener IPs y MACs de gestión antes de actualizar (Soporta fallback por lease4)
                var rebootTargets = new List<(string Ip, string Mac)>();
                await using (var cmdGetActive = _dataSource.CreateCommand(@"
                    SELECT host(COALESCE(s.ip_cm, '0.0.0.0'::inet + l.address)) as ip, e.mac::text 
                    FROM admin.servicios_clientes s
                    JOIN admin.clientes c ON s.id_cliente = c.id
                    JOIN admin.equipos e ON e.id = s.id_equipo
                    LEFT JOIN public.lease4 l ON l.hwaddr = decode(replace(e.mac::text, ':', ''), 'hex')
                    WHERE c.codigo = ANY($1) AND (s.ip_cm IS NOT NULL OR l.address IS NOT NULL);"))
                {
                    cmdGetActive.Parameters.AddWithValue(cleanCodigos);
                    await using var readerActive = await cmdGetActive.ExecuteReaderAsync();
                    while (await readerActive.ReadAsync())
                    {
                        rebootTargets.Add((readerActive.GetString(0), readerActive.GetString(1)));
                    }
                }

                // B. Un único UPDATE masivo uniendo con admin.clientes utilizando ANY
                await using var cmd = _dataSource.CreateCommand(@"
                    UPDATE admin.servicios_clientes s
                    SET estado = $1, fecha_modificacion = NOW()
                    FROM admin.clientes c
                    WHERE s.id_cliente = c.id AND c.codigo = ANY($2)
                    RETURNING s.id;");

                cmd.Parameters.AddWithValue(dto.NuevoEstado);
                cmd.Parameters.AddWithValue(cleanCodigos);

                var affectedList = new List<int>();
                await using (var reader = await cmd.ExecuteReaderAsync())
                {
                    while (await reader.ReadAsync())
                    {
                        affectedList.Add(reader.GetInt32(0));
                    }
                }

                // C. Encolar reinicios masivos
                foreach (var target in rebootTargets)
                {
                    _rebootQueue.EnqueueReboot(target.Ip, target.Mac);
                }

                return Ok(new
                {
                    Procesados = affectedList.Count,
                    EstadoAplicado = dto.NuevoEstado,
                    Message = $"Se actualizaron {affectedList.Count} suscripciones correspondientes a los códigos provistos, y se inyectaron en la cola de reinicios masivos seguros."
                });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error en la transacción masiva por códigos: {ex.Message}" });
            }
        }


        // 5. BAJA COMPLETA DE SERVICIO (DELETE /api/servicios/{id})
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            await using var connection = await _dataSource.OpenConnectionAsync();
            await using var transaction = await connection.BeginTransactionAsync();
            try
            {
                await SetSessionOperatorAsync(connection, transaction);
                
                await using var cmd = new NpgsqlCommand("DELETE FROM admin.servicios_clientes WHERE id = $1 RETURNING id;", connection, transaction);
                cmd.Parameters.AddWithValue(id);

                var result = await cmd.ExecuteScalarAsync();
                if (result == null)
                {
                    await transaction.RollbackAsync();
                    return NotFound(new { Error = $"La suscripción con ID {id} no fue encontrada" });
                }

                await transaction.CommitAsync();
                return Ok(new
                {
                    Id = id,
                    Message = "Suscripción eliminada comercialmente y liberada del DHCP. El módem ha regresado a stock como INVENTARIO."
                });
            }
            catch (Exception ex)
            {
                await transaction.RollbackAsync();
                return BadRequest(new { Error = $"Error al dar de baja el servicio: {ex.Message}" });
            }
        }

        private async Task<string> ResolveAutoIpAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, int idCmts, string tipo)
        {
            int subredId;
            await using (var cmdGetSubred = new NpgsqlCommand(@"
                SELECT s.id FROM admin.subredes s
                JOIN admin.pools p ON p.id_subred = s.id
                WHERE s.id_cmts = $1 AND s.tipo = $2 AND p.id_paquete IS NULL
                LIMIT 1;", connection, transaction))
            {
                cmdGetSubred.Parameters.AddWithValue(idCmts);
                cmdGetSubred.Parameters.AddWithValue(tipo);

                var res = await cmdGetSubred.ExecuteScalarAsync();
                if (res == null)
                {
                    throw new Exception($"No se encontró ninguna subred de tipo '{tipo}' activa en el CMTS con ID {idCmts}. No se puede realizar auto-asignación.");
                }
                subredId = Convert.ToInt32(res);
            }

            await using (var cmdGetIp = new NpgsqlCommand("SELECT admin.get_next_free_ip($1, NULL);", connection, transaction))
            {
                cmdGetIp.Parameters.AddWithValue(subredId);

                var ipResult = await cmdGetIp.ExecuteScalarAsync();
                if (ipResult == null || ipResult == DBNull.Value)
                {
                    throw new Exception($"No hay direcciones IP estáticas libres disponibles en los pools reservados para subredes '{tipo}' de este CMTS.");
                }

                return ipResult.ToString()!;
            }
        }

        private async Task SetSessionOperatorAsync(NpgsqlConnection connection, NpgsqlTransaction transaction)
        {
            var claimId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
            if (!string.IsNullOrEmpty(claimId) && Guid.TryParse(claimId, out var operadorId))
            {
                await using var cmd = new NpgsqlCommand($"SET LOCAL app.current_operator_id = '{operadorId}';", connection, transaction);
                await cmd.ExecuteNonQueryAsync();
            }
        }
    }
}
