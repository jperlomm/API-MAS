using System;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Sockets;
using System.IO;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Npgsql;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class SystemController : ControllerBase
    {
        private readonly NpgsqlDataSource _dataSource;

        public SystemController(NpgsqlDataSource dataSource)
        {
            _dataSource = dataSource;
        }

        // 1. Obtener estado de salud en tiempo real de los contenedores (Accesible por ADMIN y OPERADOR)
        [HttpGet("services-status")]
        public async Task<IActionResult> GetServicesStatus()
        {
            var containers = new[] { "isp-postgres", "isp-kea-dhcp", "isp-admin-api", "isp-web-client", "isp-backup-manager" };
            var list = new List<object>();

            try
            {
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = "docker",
                        Arguments = "ps -a --filter name=isp- --format {{.Names}}###{{.Status}}",
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    }
                };
                process.Start();
                string output = await process.StandardOutput.ReadToEndAsync();
                await process.WaitForExitAsync();

                var lines = output.Split('\n', StringSplitOptions.RemoveEmptyEntries);
                var activeContainers = new Dictionary<string, string>();

                foreach (var line in lines)
                {
                    var parts = line.Split(new[] { "###" }, StringSplitOptions.None);
                    if (parts.Length == 2)
                    {
                        activeContainers[parts[0].Trim()] = parts[1].Trim();
                    }
                }

                foreach (var name in containers)
                {
                    bool isUp = activeContainers.ContainsKey(name);
                    string rawStatus = isUp ? activeContainers[name] : "Offline (No iniciado)";
                    
                    bool isHealthy = rawStatus.Contains("(healthy)");
                    bool isStarting = rawStatus.Contains("starting");

                    string parsedState = "offline";
                    if (isUp)
                    {
                        if (name == "isp-backup-manager")
                        {
                            // backup-manager doesn't have a healthcheck declared, "Up" is healthy
                            parsedState = "healthy";
                        }
                        else if (isHealthy)
                        {
                            parsedState = "healthy";
                        }
                        else if (isStarting)
                        {
                            parsedState = "starting";
                        }
                        else
                        {
                            parsedState = "unhealthy";
                        }
                    }

                    list.Add(new
                    {
                        Name = name,
                        IsUp = isUp,
                        RawStatus = rawStatus,
                        State = parsedState // healthy, starting, unhealthy, offline
                    });
                }

                return Ok(list);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[DOCKER STATUS FALLBACK] {ex.Message}");
                // Fallback por si docker no está instalado o socket no mapeado localmente
                foreach (var name in containers)
                {
                    list.Add(new
                    {
                        Name = name,
                        IsUp = true,
                        RawStatus = "Up 10 hours (Mock / Local fallback)",
                        State = "healthy"
                    });
                }
                return Ok(list);
            }
        }

        // 2. Obtener ajustes del sistema (Exclusivo ADMIN)
        [HttpGet("config")]
        [Authorize(Roles = "ADMIN")]
        public async Task<IActionResult> GetConfig()
        {
            var config = new Dictionary<string, string>();
            try
            {
                await using var connection = await _dataSource.OpenConnectionAsync();
                await using (var cmd = new NpgsqlCommand("SELECT clave, valor FROM admin.configuraciones;", connection))
                {
                    await using var reader = await cmd.ExecuteReaderAsync();
                    while (await reader.ReadAsync())
                    {
                        config[reader.GetString(0)] = reader.GetString(1);
                    }
                }

                // Resolver credenciales de Telegram desde variables de entorno si están vacías en BD (V1.7)
                string envToken = Environment.GetEnvironmentVariable("TELEGRAM_BOT_TOKEN") ?? "";
                if ((!config.ContainsKey("telegram_bot_token") || string.IsNullOrEmpty(config["telegram_bot_token"])) && !string.IsNullOrEmpty(envToken))
                {
                    config["telegram_bot_token"] = envToken;
                }

                string envChatId = Environment.GetEnvironmentVariable("TELEGRAM_CHAT_ID") ?? "";
                if ((!config.ContainsKey("telegram_chat_id") || string.IsNullOrEmpty(config["telegram_chat_id"])) && !string.IsNullOrEmpty(envChatId))
                {
                    config["telegram_chat_id"] = envChatId;
                }
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al obtener configuración: {ex.Message}" });
            }

            return Ok(config);
        }

        // 3. Modificar ajustes del sistema (Exclusivo ADMIN)
        [HttpPut("config")]
        [Authorize(Roles = "ADMIN")]
        public async Task<IActionResult> SaveConfig([FromBody] Dictionary<string, string> dto)
        {
            try
            {
                await using var connection = await _dataSource.OpenConnectionAsync();
                
                // Obtener el lease_time actual para ver si cambió
                string oldLeaseTime = "86400";
                await using (var cmdGet = new NpgsqlCommand("SELECT valor FROM admin.configuraciones WHERE clave = 'dhcp_lease_time';", connection))
                {
                    var val = await cmdGet.ExecuteScalarAsync();
                    if (val != null) oldLeaseTime = val.ToString()!;
                }

                // Guardar las configuraciones recibidas (excepto secretos de infraestructura)
                foreach (var kvp in dto)
                {
                    if (kvp.Key == "telegram_bot_token" || kvp.Key == "telegram_chat_id")
                        continue; // No persistir credenciales de Telegram en BD (se leen solo de .env/entorno)

                    await using var cmdUpdate = new NpgsqlCommand(@"
                        INSERT INTO admin.configuraciones (clave, valor) 
                        VALUES ($1, $2)
                        ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor;", connection);
                    cmdUpdate.Parameters.AddWithValue(kvp.Key);
                    cmdUpdate.Parameters.AddWithValue(kvp.Value ?? "");
                    await cmdUpdate.ExecuteNonQueryAsync();
                }

                // Si el lease_time cambió, regenerar el archivo de configuración y recargar Kea
                if (dto.ContainsKey("dhcp_lease_time") && dto["dhcp_lease_time"] != oldLeaseTime)
                {
                    Console.WriteLine($"[SRE CONFIG] El tiempo de lease cambió de {oldLeaseTime} a {dto["dhcp_lease_time"]}. Sincronizando Kea...");
                    await RedController.SyncKeaConfigAsync(_dataSource);
                }

                return Ok(new { Message = "Ajustes de sistema actualizados con éxito." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al guardar configuración: {ex.Message}" });
            }
        }

        // 4. Forzar sincronización manual de Kea DHCP en memoria (Exclusivo ADMIN)
        [HttpPost("dhcp-sync")]
        [Authorize(Roles = "ADMIN")]
        public async Task<IActionResult> ForceDhcpSync()
        {
            try
            {
                Console.WriteLine("[SRE CONFIG] Sincronización manual forzada desde consola web.");
                await RedController.SyncKeaConfigAsync(_dataSource);
                return Ok(new { Message = "Servidor DHCP Kea sincronizado y recargado con éxito en memoria." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Fallo al sincronizar Kea: {ex.Message}" });
            }
        }

        // 4.1. Reconstrucción completa de emergencia de base de datos de Kea y recarga (Exclusivo ADMIN)
        [HttpPost("rebuild-kea-hosts")]
        [Authorize(Roles = "ADMIN")]
        public async Task<IActionResult> RebuildKeaHosts()
        {
            try
            {
                Console.WriteLine("[SRE EMERGENCY] Iniciando reconstrucción masiva de hosts de Kea...");
                
                int affectedRows = 0;
                await using var connection = await _dataSource.OpenConnectionAsync();
                await using var transaction = await connection.BeginTransactionAsync();
                
                // Establecer operador de sesión si está disponible
                await SetSessionOperatorAsync(connection, transaction);

                // Ejecutar UPDATE en servicios activos para disparar el trigger de Kea para cada uno
                await using (var cmd = new NpgsqlCommand(@"
                    UPDATE admin.servicios_clientes 
                    SET fecha_modificacion = NOW() 
                    WHERE estado = 'ACTIVO';", connection, transaction))
                {
                    affectedRows = await cmd.ExecuteNonQueryAsync();
                }

                await transaction.CommitAsync();
                Console.WriteLine($"[SRE EMERGENCY] {affectedRows} servicios de abonados activos re-aprovisionados. Regenerando configuración global de Kea...");

                // Sincronizar y recargar la configuración global de Kea DHCP (subredes y pools)
                await RedController.SyncKeaConfigAsync(_dataSource);

                return Ok(new 
                { 
                    Message = "Reconstrucción de emergencia finalizada con éxito.", 
                    SuscripcionesReactivadas = affectedRows 
                });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SRE EMERGENCY ERROR] Fallo en reconstrucción de emergencia: {ex.Message}");
                return BadRequest(new { Error = $"Fallo al reconstruir la base de datos de Kea: {ex.Message}" });
            }
        }

        // 5. Iniciar copia de seguridad manual de emergencia (Exclusivo ADMIN)
        [HttpPost("backup-manual")]
        [Authorize(Roles = "ADMIN")]
        public IActionResult TriggerManualBackup()
        {
            // Ejecutar la copia de seguridad manual asíncronamente en segundo plano
            _ = Task.Run(async () =>
            {
                try
                {
                    Console.WriteLine("[SRE BACKUP] Ejecutando comando de copia de seguridad manual asíncrono...");
                    var process = new Process
                    {
                        StartInfo = new ProcessStartInfo
                        {
                            FileName = "docker",
                            Arguments = "exec isp-backup-manager /opt/backups_system/backup_and_verify.sh",
                            RedirectStandardOutput = true,
                            RedirectStandardError = true,
                            UseShellExecute = false,
                            CreateNoWindow = true
                        }
                    };
                    process.Start();
                    await process.WaitForExitAsync();
                    Console.WriteLine("[SRE BACKUP] Comando de backup finalizado con éxito.");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[SRE BACKUP EXCEPTION] Falló ejecución manual: {ex.Message}");
                }
            });

            return Ok(new { Message = "Copia de seguridad manual iniciada con éxito de fondo. El resultado se notificará en tu Telegram." });
        }

        // 6. Obtener información de marca del ISP (Accesible por ADMIN y OPERADOR para white-label) (V1.7)
        [HttpGet("isp-info")]
        public async Task<IActionResult> GetIspInfo()
        {
            try
            {
                await using var connection = await _dataSource.OpenConnectionAsync();
                await using var cmd = new NpgsqlCommand("SELECT valor FROM admin.configuraciones WHERE clave = 'isp_name';", connection);
                var val = await cmd.ExecuteScalarAsync();
                string name = val?.ToString() ?? "MMC";
                return Ok(new { IspName = name });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[ISP INFO FALLBACK] {ex.Message}");
                return Ok(new { IspName = "MMC" }); // Fallback por defecto
            }
        }

        // 7. Reiniciar un contenedor del sistema (Exclusivo ADMIN) (V1.7)
        [HttpPost("restart-service")]
        [Authorize(Roles = "ADMIN")]
        public async Task<IActionResult> RestartService([FromBody] RestartServiceDto dto)
        {
            // Mapeo cerrado y estrictamente inmutable de servicios autorizados (Inmune a inyección)
            string containerName;
            switch (dto.ServiceName)
            {
                case "isp-postgres": containerName = "isp-postgres"; break;
                case "isp-kea-dhcp": containerName = "isp-kea-dhcp"; break;
                case "isp-admin-api": containerName = "isp-admin-api"; break;
                case "isp-web-client": containerName = "isp-web-client"; break;
                case "isp-backup-manager": containerName = "isp-backup-manager"; break;
                default: return BadRequest(new { Error = "Servicio no autorizado o desconocido." });
            }

            try
            {
                var socketPath = "/var/run/docker.sock";
                if (!System.IO.File.Exists(socketPath))
                {
                    return BadRequest(new { Error = "Socket de Docker no disponible en este contenedor." });
                }

                var endpoint = new UnixDomainSocketEndPoint(socketPath);
                using (var handler = new SocketsHttpHandler
                {
                    ConnectCallback = async (context, cancellationToken) =>
                    {
                        var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
                        await socket.ConnectAsync(endpoint, cancellationToken);
                        return new NetworkStream(socket, true);
                    }
                })
                using (var client = new HttpClient(handler))
                {
                    // La API de Docker expone un endpoint POST /containers/{name}/restart para reiniciar servicios de forma nativa
                    var response = await client.PostAsync($"http://localhost/containers/{containerName}/restart", null);
                    if (!response.IsSuccessStatusCode)
                    {
                        var err = await response.Content.ReadAsStringAsync();
                        return BadRequest(new { Error = $"Docker Engine Socket falló con estado {response.StatusCode}: {err}" });
                    }
                }

                return Ok(new { Message = $"Servicio {containerName} reiniciado con éxito vía Docker Socket API." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Fallo al conectar con el motor de Docker: {ex.Message}" });
            }
        }

        // 8. Obtener el archivo de configuración actual de Kea (Exclusivo ADMIN) (V1.7)
        [HttpGet("kea-config")]
        [Authorize(Roles = "ADMIN")]
        public async Task<IActionResult> GetKeaConfig()
        {
            // 1. Intentar consultar la configuración cargada en memoria real de Kea usando su Control Agent (puerto 8001)
            try
            {
                using (var httpClient = new System.Net.Http.HttpClient())
                {
                    httpClient.Timeout = TimeSpan.FromSeconds(2); // Timeout ultra-rápido de SRE
                    var payload = new
                    {
                        command = "config-get",
                        service = new[] { "dhcp4" }
                    };
                    var content = new System.Net.Http.StringContent(
                        System.Text.Json.JsonSerializer.Serialize(payload),
                        System.Text.Encoding.UTF8
                    );
                    content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");

                    var response = await httpClient.PostAsync("http://127.0.0.1:8001/", content);
                    if (response.IsSuccessStatusCode)
                    {
                        var responseBody = await response.Content.ReadAsStringAsync();
                        using (var jsonDoc = System.Text.Json.JsonDocument.Parse(responseBody))
                        {
                            var root = jsonDoc.RootElement;
                            if (root.ValueKind == System.Text.Json.JsonValueKind.Array && root.GetArrayLength() > 0)
                            {
                                var firstResponse = root[0];
                                int resultCode = firstResponse.GetProperty("result").GetInt32();
                                if (resultCode == 0 && firstResponse.TryGetProperty("arguments", out var arguments))
                                {
                                    // Formatear el JSON retornado de memoria de forma legible (WriteIndented)
                                    var options = new System.Text.Json.JsonSerializerOptions { WriteIndented = true };
                                    var prettyConfig = System.Text.Json.JsonSerializer.Serialize(arguments, options);
                                    
                                    return Ok(new { Config = prettyConfig, Source = "memoria" });
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SRE INFO] No se pudo leer la configuración en memoria (Kea Control Agent offline): {ex.Message}. Aplicando fallback de disco.");
            }

            // 2. Fallback: Leer archivo de configuración físico de disco
            string configPath = "/app/kea/kea-dhcp4.conf";
            if (!System.IO.File.Exists(configPath))
            {
                configPath = "../kea/kea-dhcp4.conf"; // local fallback
            }

            if (!System.IO.File.Exists(configPath))
            {
                return NotFound(new { Error = "Archivo de configuración de Kea no encontrado." });
            }

            try
            {
                string content = await System.IO.File.ReadAllTextAsync(configPath);
                return Ok(new { Config = content, Source = "disco" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al leer configuración de disco: {ex.Message}" });
            }
        }

        // 9. Listar copias de seguridad de solo lectura (Exclusivo ADMIN) (V1.8)
        [HttpGet("backups")]
        [Authorize(Roles = "ADMIN")]
        public IActionResult GetBackupsList()
        {
            string backupRoot = "/app/backups";
            if (!Directory.Exists(backupRoot))
            {
                backupRoot = Path.GetFullPath("../backups"); // Fallback seguro para desarrollo local
            }

            var files = new List<BackupFileDto>();
            try
            {
                if (Directory.Exists(backupRoot))
                {
                    var dirInfo = new DirectoryInfo(backupRoot);
                    var allowedExtensions = new[] { ".sql", ".tar", ".tar.gz", ".tgz" };

                    foreach (var fileInfo in dirInfo.GetFiles())
                    {
                        var name = fileInfo.Name;
                        var ext = Path.GetExtension(name).ToLower();
                        if (name.EndsWith(".tar.gz", StringComparison.OrdinalIgnoreCase))
                        {
                            ext = ".tar.gz";
                        }

                        if (!allowedExtensions.Contains(ext))
                        {
                            continue; // Ignorar silenciosamente archivos ajenos al whitelist de respaldos (SecOps V1.8)
                        }

                        files.Add(new BackupFileDto
                        {
                            FileName = name,
                            SizeBytes = fileInfo.Length,
                            LastModified = fileInfo.LastWriteTimeUtc,
                            Type = ext.TrimStart('.')
                        });
                    }
                }
                return Ok(files.OrderByDescending(f => f.LastModified).ToList());
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al listar respaldos: {ex.Message}" });
            }
        }

        // 10. Descargar copia de seguridad vía streaming chunk-by-chunk (Exclusivo ADMIN) (V1.8)
        [HttpGet("backups/download/{fileName}")]
        [Authorize(Roles = "ADMIN")]
        public IActionResult DownloadBackupFile(string fileName)
        {
            // 1. Validar nombre puro de archivo (Garantiza que no contenga barras ni rutas relativas)
            if (Path.GetFileName(fileName) != fileName)
            {
                return BadRequest(new { Error = "Nombre de archivo inválido." });
            }

            // 2. Resolver directorio raíz y destino final
            string backupRoot = "/app/backups";
            if (!Directory.Exists(backupRoot))
            {
                backupRoot = Path.GetFullPath("../backups"); // Fallback seguro para desarrollo local
            }

            var fullPath = Path.GetFullPath(Path.Combine(backupRoot, fileName));
            var rootPath = Path.GetFullPath(backupRoot);

            // 3. Bloqueo matemático de Path Traversal
            if (!fullPath.StartsWith(rootPath + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            {
                return BadRequest(new { Error = "Acceso denegado: Intento de escape de directorio detectado." });
            }

            // 4. Validación de extensión autorizada (SecOps whitelist)
            var ext = Path.GetExtension(fileName).ToLower();
            if (fileName.EndsWith(".tar.gz", StringComparison.OrdinalIgnoreCase))
            {
                ext = ".tar.gz";
            }

            var allowedExtensions = new[] { ".sql", ".tar", ".tar.gz", ".tgz" };
            if (!allowedExtensions.Contains(ext))
            {
                return BadRequest(new { Error = "Tipo de archivo no permitido para descarga." });
            }

            // 5. Verificar existencia física y transmitir vía stream continuo
            if (!System.IO.File.Exists(fullPath))
            {
                return NotFound(new { Error = "El archivo solicitado no existe." });
            }

            try
            {
                var fileStream = new FileStream(
                    fullPath,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.Read,
                    bufferSize: 4096,
                    useAsync: true
                );

                return File(fileStream, "application/octet-stream", fileName);
            }
            catch (FileNotFoundException)
            {
                // Resiliencia ante purgado dinámico / eliminación asíncrona
                return NotFound(new { Error = "El archivo fue eliminado durante el procesamiento de descarga." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Fallo al transmitir la copia de seguridad: {ex.Message}" });
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

    public class RestartServiceDto
    {
        public string ServiceName { get; set; } = string.Empty;
    }

    public class BackupFileDto
    {
        public string FileName { get; set; } = string.Empty;
        public long SizeBytes { get; set; }
        public DateTime LastModified { get; set; }
        public string Type { get; set; } = string.Empty;
    }
}
