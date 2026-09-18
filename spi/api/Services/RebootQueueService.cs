using System.Threading.Channels;
using System.Diagnostics;

namespace SmiApi.Services
{
    public class RebootQueueService : BackgroundService
    {
        // Cola asíncrona ultra rápida y libre de bloqueos de hilos (thread-safe)
        private readonly Channel<RebootTask> _rebootChannel = Channel.CreateUnbounded<RebootTask>();
        private readonly ILogger<RebootQueueService> _logger;
        private readonly string _snmpCommunity;

        public class RebootTask
        {
            public string IpCm { get; set; } = null!;
            public string Mac { get; set; } = null!;
        }

        public RebootQueueService(ILogger<RebootQueueService> logger, IConfiguration configuration)
        {
            _logger = logger;
            // Leer comunidad de escritura SNMP desde la configuración (.env/appsettings), por defecto 'public'
            _snmpCommunity = configuration["SNMP_COMMUNITY"] ?? "public";
        }

        // Método público expuesto para que los controladores encolen módems para reiniciar
        public void EnqueueReboot(string ipCm, string mac)
        {
            if (string.IsNullOrWhiteSpace(ipCm)) return;

            var task = new RebootTask { IpCm = ipCm, Mac = mac };
            if (_rebootChannel.Writer.TryWrite(task))
            {
                _logger.LogDebug($"Encolado reinicio para Cablemódem: {mac} (IP: {ipCm})");
            }
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("Iniciando el despachador de reinicios DOCSIS en segundo plano...");

            // Leer de la cola asíncrona de forma indefinida sin bloquear hilos ni gastar CPU
            await foreach (var task in _rebootChannel.Reader.ReadAllAsync(stoppingToken))
            {
                try
                {
                    // Despachar comando de reinicio SNMPv2 DocsDevResetNow (OID: 1.3.6.1.2.1.69.1.1.3.0)
                    // docsDevResetNow.0 = 1 (Integer 1: resetNow)
                    _logger.LogInformation($"[REBOOT QUEUE] Despachando reinicio a CM MAC: {task.Mac} en IP: {task.IpCm}");

                    // Lanzar comando de consola snmpset nativo de Linux (ultra-rápido y estable)
                    using var process = new Process();
                    process.StartInfo.FileName = "snmpset";
                    process.StartInfo.Arguments = $"-v2c -c {_snmpCommunity} -t 1 -r 1 {task.IpCm} 1.3.6.1.2.1.69.1.1.3.0 i 1";
                    process.StartInfo.RedirectStandardOutput = true;
                    process.StartInfo.RedirectStandardError = true;
                    process.StartInfo.UseShellExecute = false;
                    process.StartInfo.CreateNoWindow = true;

                    process.Start();
                    
                    // Esperar un máximo de 1.5 segundos a que la red física responda
                    await process.WaitForExitAsync(stoppingToken);

                    if (process.ExitCode == 0)
                    {
                        _logger.LogDebug($"[REBOOT QUEUE] Comando SNMP Reset exitoso para IP: {task.IpCm}");
                    }
                    else
                    {
                        var stderr = await process.StandardError.ReadToEndAsync(stoppingToken);
                        _logger.LogWarning($"[REBOOT QUEUE] Alerta de reinicio en {task.IpCm}: {stderr.Trim()}");
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError($"[REBOOT QUEUE] Excepción al reiniciar Cablemódem {task.Mac} ({task.IpCm}): {ex.Message}");
                }

                // --- ⚡ EL SECRETO DEL THROTTLING (Tasa Limitada) ⚡ ---
                // Esperar exactamente 20 milisegundos entre cada envío de comandos.
                // Esto limita de forma física la tasa de reinicios a un máximo de 50 módems por segundo (50 Hz).
                // Evita tsunamis de tráfico en el TFTP, en el canal de retorno de RF y protege la CPU del CMTS.
                await Task.Delay(20, stoppingToken);
            }
        }
    }
}
