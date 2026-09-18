using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

namespace SmiApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class BootfilesController : ControllerBase
    {
        private readonly string _tftpDir;
        private readonly ILogger<BootfilesController> _logger;

        public BootfilesController(IConfiguration configuration, ILogger<BootfilesController> logger)
        {
            _logger = logger;
            // Directorio compartido del TFTP, por defecto /app/tftp/
            _tftpDir = configuration["TFTP_DIRECTORY"] ?? "/app/tftp";

            // Asegurar que el directorio de compilación física exista
            if (!Directory.Exists(_tftpDir))
            {
                Directory.CreateDirectory(_tftpDir);
            }
        }

        public class CompileRequestDto
        {
            public string Filename { get; set; } = null!; // Nombre sin extensión, ej: 'plan-100m'
            public string Content { get; set; } = null!;  // Configuración plana en texto DOCSIS
        }

        // 1. LISTAR ARCHIVOS EN EL TFTP (GET /api/bootfiles)
        [HttpGet]
        public IActionResult ListFiles()
        {
            try
            {
                var files = Directory.GetFiles(_tftpDir)
                    .Select(Path.GetFileName)
                    .Where(f => f != null)
                    .Select(f => {
                        var ext = (Path.GetExtension(f) ?? "").ToLower();
                        string typeLabel = ext switch
                        {
                            ".bin" => "Compilado (.bin)",
                            ".bat" => "Script (.bat)",
                            ".txt" => "Texto Plano (.txt)",
                            ".key" => "Clave (.key)",
                            _ => "Archivo"
                        };
                        return new
                        {
                            Name = f,
                            Type = typeLabel,
                            Size = new FileInfo(Path.Combine(_tftpDir, f!)).Length,
                            LastModified = new FileInfo(Path.Combine(_tftpDir, f!)).LastWriteTime
                        };
                    })
                    .OrderBy(f => f.Name)
                    .ToList();

                return Ok(files);
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al listar archivos del TFTP: {ex.Message}" });
            }
        }

        // 2. LEER CONTENIDO DE UN ARCHIVO DE TEXTO (GET /api/bootfiles/{filename})
        [HttpGet("{filename}")]
        public async Task<IActionResult> GetFileContent(string filename)
        {
            // Evitar Path Traversal / Vulnerabilidad de Seguridad de acceso a carpetas superiores
            if (filename.Contains("..") || Path.GetFileName(filename) != filename)
            {
                return BadRequest(new { Error = "Nombre de archivo inválido por motivos de seguridad" });
            }

            var ext = (Path.GetExtension(filename) ?? "").ToLower();
            if (ext != ".txt" && ext != ".bat" && ext != ".key")
            {
                return BadRequest(new { Error = "Solo se permite visualizar el contenido de archivos .txt, .bat y .key." });
            }

            var filePath = Path.Combine(_tftpDir, filename);

            if (!System.IO.File.Exists(filePath))
            {
                return NotFound(new { Error = $"El archivo '{filename}' no existe en el TFTP." });
            }

            try
            {
                var content = await System.IO.File.ReadAllTextAsync(filePath);
                return Ok(new { Filename = filename, Content = content });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al leer el archivo: {ex.Message}" });
            }
        }

        // 2B. SUBIR UN ARCHIVO AL TFTP (POST /api/bootfiles/upload)
        [HttpPost("upload")]
        public async Task<IActionResult> UploadFile(IFormFile file)
        {
            if (file == null || file.Length == 0)
            {
                return BadRequest(new { Error = "No se ha seleccionado ningún archivo para subir." });
            }

            var filename = Path.GetFileName(file.FileName);
            if (filename.Contains("..") || Path.GetFileName(filename) != filename)
            {
                return BadRequest(new { Error = "Nombre de archivo inválido." });
            }

            var ext = (Path.GetExtension(filename) ?? "").ToLower();
            if (ext != ".bin" && ext != ".txt" && ext != ".bat" && ext != ".key")
            {
                return BadRequest(new { Error = "Extensión de archivo no permitida. Solo se admiten archivos .bin, .txt, .bat y .key." });
            }

            var targetPath = Path.Combine(_tftpDir, filename);

            try
            {
                _logger.LogInformation($"[TFTP] Subiendo archivo: {filename} a {targetPath}");
                await using var stream = new FileStream(targetPath, FileMode.Create);
                await file.CopyToAsync(stream);
                return Ok(new { Message = $"El archivo '{filename}' ha sido subido e instalado correctamente en el servidor TFTP." });
            }
            catch (Exception ex)
            {
                _logger.LogError($"[TFTP] Error al subir archivo {filename}: {ex.Message}");
                return BadRequest(new { Error = $"Error al guardar el archivo: {ex.Message}" });
            }
        }

        // 3. GUARDAR Y COMPILAR BOOTFILE DOCSIS A BINARIO (POST /api/bootfiles/compile)
        [HttpPost("compile")]
        public async Task<IActionResult> CompileBootfile([FromBody] CompileRequestDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.Filename) || string.IsNullOrWhiteSpace(dto.Content))
            {
                return BadRequest(new { Error = "El nombre del archivo y el contenido de texto son obligatorios" });
            }

            // Sanitizar nombre de archivo contra Path Traversal
            var cleanFilename = Path.GetFileNameWithoutExtension(dto.Filename).Replace(" ", "_").Trim();
            if (string.IsNullOrWhiteSpace(cleanFilename) || cleanFilename.Contains(".."))
            {
                return BadRequest(new { Error = "Nombre de archivo inválido" });
            }

            var txtPath = Path.Combine(_tftpDir, $"{cleanFilename}.txt");
            var binPath = Path.Combine(_tftpDir, $"{cleanFilename}.bin");

            try
            {
                _logger.LogInformation($"[COMPILER] Guardando archivo de texto plano: {txtPath}");
                // 1. Guardar la especificación en texto plano (.txt) de forma asíncrona
                await System.IO.File.WriteAllTextAsync(txtPath, dto.Content);

                _logger.LogInformation($"[COMPILER] Iniciando compilación de {cleanFilename}.txt a {cleanFilename}.bin...");

                // Asegurar la existencia de un archivo de clave (shared.key) para firmar el MIC de DOCSIS
                var keyPath = Path.Combine(_tftpDir, "shared.key");
                if (!System.IO.File.Exists(keyPath))
                {
                    await System.IO.File.WriteAllTextAsync(keyPath, "secret");
                }

                // 2. Invocar el binario oficial de Linux 'docsis' para compilar
                // Sintaxis: docsis -e <archivo_texto> <archivo_key> <archivo_binario>
                using var process = new Process();
                process.StartInfo.FileName = "docsis";
                process.StartInfo.Arguments = $"-e \"{txtPath}\" \"{keyPath}\" \"{binPath}\"";
                process.StartInfo.RedirectStandardOutput = true;
                process.StartInfo.RedirectStandardError = true;
                process.StartInfo.UseShellExecute = false;
                process.StartInfo.CreateNoWindow = true;

                process.Start();

                var stdoutTask = process.StandardOutput.ReadToEndAsync();
                var stderrTask = process.StandardError.ReadToEndAsync();

                await process.WaitForExitAsync();

                var stdout = await stdoutTask;
                var stderr = await stderrTask;

                if (process.ExitCode == 0)
                {
                    _logger.LogInformation($"[COMPILER] Compilación exitosa para {cleanFilename}.bin");
                    return Ok(new
                    {
                        Filename = $"{cleanFilename}.bin",
                        Size = new FileInfo(binPath).Length,
                        Log = stdout.Trim() != "" ? stdout : "Compilación exitosa (sin advertencias)",
                        Message = "Archivo de configuración DOCSIS compilado y publicado con éxito en el servidor TFTP"
                    });
                }
                else
                {
                    _logger.LogWarning($"[COMPILER] Fallo en la compilación de {cleanFilename}. Error: {stderr}");

                    // Filtrar ruidos e inundaciones de advertencias de Net-SNMP para dejar solo el error real de compilación
                    var cleanStderr = string.Join("\n", stderr.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                        .Where(line => !line.Contains("Unlinked OID") && 
                                       !line.Contains("Undefined identifier") && 
                                       !line.Contains("Cannot adopt OID") && 
                                       !line.Contains("MIB search path") && 
                                       !line.Contains("Cannot adopt")));

                    return BadRequest(new
                    {
                        Error = "Error de sintaxis en el archivo de configuración DOCSIS",
                        Details = !string.IsNullOrWhiteSpace(cleanStderr) ? cleanStderr : "Fallo desconocido en el compilador 'docsis'"
                    });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError($"[COMPILER] Excepción al compilar: {ex.Message}");
                return BadRequest(new { Error = $"Excepción interna al procesar compilación: {ex.Message}" });
            }
        }

        // 4. ELIMINAR BOOTFILE (DELETE /api/bootfiles/{filename})
        [HttpDelete("{filename}")]
        public IActionResult DeleteFile(string filename)
        {
            if (string.IsNullOrWhiteSpace(filename) || filename.Contains("..") || Path.GetFileName(filename) != filename)
            {
                return BadRequest(new { Error = "Nombre de archivo inválido por motivos de seguridad" });
            }

            var cleanName = Path.GetFileNameWithoutExtension(filename);
            var txtPath = Path.Combine(_tftpDir, $"{cleanName}.txt");
            var binPath = Path.Combine(_tftpDir, $"{cleanName}.bin");

            try
            {
                bool deletedAny = false;
                if (System.IO.File.Exists(txtPath))
                {
                    System.IO.File.Delete(txtPath);
                    deletedAny = true;
                }
                if (System.IO.File.Exists(binPath))
                {
                    System.IO.File.Delete(binPath);
                    deletedAny = true;
                }

                if (deletedAny)
                {
                    _logger.LogInformation($"[COMPILER] Archivos de '{cleanName}' eliminados correctamente por el usuario");
                    return Ok(new { Message = $"El bootfile '{cleanName}' y su archivo fuente han sido eliminados correctamente" });
                }
                else
                {
                    return NotFound(new { Error = $"No se encontró ningún archivo con el nombre '{cleanName}' para eliminar" });
                }
            }
            catch (Exception ex)
            {
                return BadRequest(new { Error = $"Error al eliminar el archivo: {ex.Message}" });
            }
        }
    }
}
