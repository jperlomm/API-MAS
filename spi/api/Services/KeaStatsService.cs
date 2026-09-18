using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Npgsql;
using SmiApi.Models;

namespace SmiApi.Services
{
    public class KeaStatsService
    {
        private readonly ILogger<KeaStatsService> _logger;
        private readonly NpgsqlDataSource _dataSource;
        private readonly object _lock = new();

        public bool KeaAvailable { get; private set; } = false;
        public double? DiscoverPerMin { get; private set; }
        public double? RequestPerMin { get; private set; }
        public double? AckPerMin { get; private set; }
        public double? NakPerMin { get; private set; }
        public double? DropPerMin { get; private set; }
        public double? AckRequestRatio { get; private set; }

        public KeaStatsSample? CurrentSample { get; private set; }
        public KeaStatsSample? PreviousSample { get; private set; }

        // Hourly Accumulators & Time Slots
        private DateTime _currentHourSlot = DateTime.MinValue;
        private long _hourlyDiscover = 0;
        private long _hourlyRequest = 0;
        private long _hourlyAck = 0;
        private long _hourlyNak = 0;
        private long _hourlyDrop = 0;

        public KeaStatsService(ILogger<KeaStatsService> logger, NpgsqlDataSource dataSource)
        {
            _logger = logger;
            _dataSource = dataSource;
        }

        public async Task PollStatsAsync(CancellationToken cancellationToken)
        {
            var socketPath = "/var/run/kea/kea-dhcp4-ctrl.sock";
            if (!File.Exists(socketPath))
            {
                _logger.LogWarning($"[KeaStatsService] Unix socket not found at '{socketPath}'. Kea is likely offline or volume not mounted.");
                lock (_lock)
                {
                    KeaAvailable = false;
                    ResetBaselineInternal();
                }
                return;
            }

            // Query exactly 5 core statistics sequentially
            long? discover = await QueryKeaStatAsync(socketPath, "pkt4-discover-received", cancellationToken);
            long? request = await QueryKeaStatAsync(socketPath, "pkt4-request-received", cancellationToken);
            long? ack = await QueryKeaStatAsync(socketPath, "pkt4-ack-sent", cancellationToken);
            long? nak = await QueryKeaStatAsync(socketPath, "pkt4-nak-sent", cancellationToken);
            long? drop = await QueryKeaStatAsync(socketPath, "pkt4-receive-drop", cancellationToken);

            if (discover == null || request == null || ack == null || nak == null || drop == null)
            {
                // Any null value signifies a communication error or timeout for this cycle
                _logger.LogWarning("[KeaStatsService] One or more statistics failed to poll. Resetting monitoring baseline.");
                lock (_lock)
                {
                    KeaAvailable = false;
                    ResetBaselineInternal();
                }
                return;
            }

            var newSample = new KeaStatsSample(
                DateTime.UtcNow,
                discover.Value,
                request.Value,
                ack.Value,
                nak.Value,
                drop.Value
            );

            lock (_lock)
            {
                KeaAvailable = true;
                PreviousSample = CurrentSample;
                CurrentSample = newSample;

                if (PreviousSample != null)
                {
                    double elapsedSeconds = (CurrentSample.Timestamp - PreviousSample.Timestamp).TotalSeconds;
                    if (elapsedSeconds > 0)
                    {
                        long deltaDiscover = 0;
                        long deltaRequest = 0;
                        long deltaAck = 0;
                        long deltaNak = 0;
                        long deltaDrop = 0;
                        bool isReset = false;

                        // Counter Reset Detection (Kea restarted or manual statistics-reset)
                        if (CurrentSample.Discover < PreviousSample.Discover ||
                            CurrentSample.Request < PreviousSample.Request ||
                            CurrentSample.Ack < PreviousSample.Ack ||
                            CurrentSample.Nak < PreviousSample.Nak ||
                            CurrentSample.Drop < PreviousSample.Drop)
                        {
                            _logger.LogInformation("[KeaStatsService] Kea counter reset detected (reboot). Clearing previous baseline.");
                            isReset = true;
                            deltaDiscover = CurrentSample.Discover;
                            deltaRequest = CurrentSample.Request;
                            deltaAck = CurrentSample.Ack;
                            deltaNak = CurrentSample.Nak;
                            deltaDrop = CurrentSample.Drop;
                            ResetBaselineInternal();
                        }
                        else
                        {
                            deltaDiscover = CurrentSample.Discover - PreviousSample.Discover;
                            deltaRequest = CurrentSample.Request - PreviousSample.Request;
                            deltaAck = CurrentSample.Ack - PreviousSample.Ack;
                            deltaNak = CurrentSample.Nak - PreviousSample.Nak;
                            deltaDrop = CurrentSample.Drop - PreviousSample.Drop;
                        }

                        if (!isReset)
                        {
                            // Calculate rates per minute over the elapsed duration
                            DiscoverPerMin = (deltaDiscover / elapsedSeconds) * 60.0;
                            RequestPerMin = (deltaRequest / elapsedSeconds) * 60.0;
                            AckPerMin = (deltaAck / elapsedSeconds) * 60.0;
                            NakPerMin = (deltaNak / elapsedSeconds) * 60.0;
                            DropPerMin = (deltaDrop / elapsedSeconds) * 60.0;

                            // Calculate ACK / REQUEST Completion Ratio
                            if (deltaRequest > 0)
                            {
                                AckRequestRatio = ((double)deltaAck / deltaRequest) * 100.0;
                                if (AckRequestRatio > 100.0) AckRequestRatio = 100.0; // Clamp to 100% in case of slight delay
                                if (AckRequestRatio < 0.0) AckRequestRatio = 0.0;
                            }
                            else
                            {
                                AckRequestRatio = null; // No requests in this delta window
                            }
                        }

                        // =====================================================
                        // Hourly Aggregation & Time-Truncation (Case A)
                        // =====================================================
                        var sampleHourSlot = new DateTime(
                            CurrentSample.Timestamp.Year,
                            CurrentSample.Timestamp.Month,
                            CurrentSample.Timestamp.Day,
                            CurrentSample.Timestamp.Hour,
                            0,
                            0,
                            DateTimeKind.Utc);

                        if (_currentHourSlot == DateTime.MinValue)
                        {
                            _currentHourSlot = sampleHourSlot;
                        }

                        if (sampleHourSlot != _currentHourSlot)
                        {
                            // Hour transition detected! Save the completed hour
                            var hourToSave = _currentHourSlot;
                            var discVal = _hourlyDiscover;
                            var reqVal = _hourlyRequest;
                            var ackVal = _hourlyAck;
                            var nakVal = _hourlyNak;
                            var dropVal = _hourlyDrop;

                            _ = Task.Run(async () =>
                            {
                                try
                                {
                                    await SaveHourlyStatsAsync(hourToSave, discVal, reqVal, ackVal, nakVal, dropVal);
                                }
                                catch (Exception ex)
                                {
                                    _logger.LogError(ex, $"[KeaStatsService] Error saving hourly statistics for {hourToSave}: {ex.Message}");
                                }
                            });

                            // Reset accumulators for the new hour slot
                            _hourlyDiscover = isReset ? 0 : deltaDiscover;
                            _hourlyRequest = isReset ? 0 : deltaRequest;
                            _hourlyAck = isReset ? 0 : deltaAck;
                            _hourlyNak = isReset ? 0 : deltaNak;
                            _hourlyDrop = isReset ? 0 : deltaDrop;

                            _currentHourSlot = sampleHourSlot;
                        }
                        else
                        {
                            // Accumulate delta for the current hour slot
                            _hourlyDiscover += deltaDiscover;
                            _hourlyRequest += deltaRequest;
                            _hourlyAck += deltaAck;
                            _hourlyNak += deltaNak;
                            _hourlyDrop += deltaDrop;
                        }
                    }
                }
                else
                {
                    // First successful sample acts strictly as a baseline
                    DiscoverPerMin = null;
                    RequestPerMin = null;
                    AckPerMin = null;
                    NakPerMin = null;
                    DropPerMin = null;
                    AckRequestRatio = null;
                }
            }
        }

        private void ResetBaselineInternal()
        {
            PreviousSample = null;
            CurrentSample = null;
            DiscoverPerMin = null;
            RequestPerMin = null;
            AckPerMin = null;
            NakPerMin = null;
            DropPerMin = null;
            AckRequestRatio = null;
        }

        private async Task SaveHourlyStatsAsync(DateTime hora, long discovers, long requests, long acks, long naks, long drops)
        {
            _logger.LogInformation($"[KeaStatsService] Guardando agregados horarios para {hora:yyyy-MM-dd HH:mm:ss} UTC (DISCOVER={discovers}, REQUEST={requests}, ACK={acks})...");
            
            await using (var cmd = _dataSource.CreateCommand())
            {
                cmd.CommandText = @"
                    INSERT INTO admin.dhcp_hourly_stats (fecha, discovers, requests, acks, naks, drops)
                    VALUES (@fecha, @discovers, @requests, @acks, @naks, @drops)
                    ON CONFLICT (fecha)
                    DO UPDATE SET
                        discovers = EXCLUDED.discovers,
                        requests = EXCLUDED.requests,
                        acks = EXCLUDED.acks,
                        naks = EXCLUDED.naks,
                        drops = EXCLUDED.drops;
                ";

                cmd.Parameters.AddWithValue("fecha", NpgsqlTypes.NpgsqlDbType.TimestampTz, hora);
                cmd.Parameters.AddWithValue("discovers", NpgsqlTypes.NpgsqlDbType.Bigint, discovers);
                cmd.Parameters.AddWithValue("requests", NpgsqlTypes.NpgsqlDbType.Bigint, requests);
                cmd.Parameters.AddWithValue("acks", NpgsqlTypes.NpgsqlDbType.Bigint, acks);
                cmd.Parameters.AddWithValue("naks", NpgsqlTypes.NpgsqlDbType.Bigint, naks);
                cmd.Parameters.AddWithValue("drops", NpgsqlTypes.NpgsqlDbType.Bigint, drops);

                await cmd.ExecuteNonQueryAsync();
            }
        }

        private async Task<long?> QueryKeaStatAsync(string socketPath, string statName, CancellationToken cancellationToken)
        {
            var commandObj = new { command = "statistic-get", arguments = new { name = statName } };
            string jsonCommand = JsonSerializer.Serialize(commandObj);
            byte[] bytesToSend = Encoding.UTF8.GetBytes(jsonCommand);

            // Establish strict 3-second non-blocking timeout for socket operations
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(3));

            try
            {
                using var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
                await socket.ConnectAsync(new UnixDomainSocketEndPoint(socketPath), cts.Token);
                await socket.SendAsync(bytesToSend, SocketFlags.None, cts.Token);

                var responseBytes = new List<byte>();
                var buffer = new byte[4096];
                
                while (true)
                {
                    int bytesRead = await socket.ReceiveAsync(buffer, SocketFlags.None, cts.Token);
                    if (bytesRead == 0) break; // EOF (Kea closes socket after response)
                    responseBytes.AddRange(buffer.Take(bytesRead));
                }

                if (responseBytes.Count == 0) return null;

                string responseJson = Encoding.UTF8.GetString(responseBytes.ToArray());
                using var doc = JsonDocument.Parse(responseJson);
                var root = doc.RootElement;

                // Parse standard Kea response arguments payload
                if (root.TryGetProperty("arguments", out var args) &&
                    args.TryGetProperty(statName, out var statArray) &&
                    statArray.GetArrayLength() > 0)
                {
                    // Kea returns statistics in array format [[value, timestamp_string]]
                    return statArray[0][0].GetInt64();
                }
            }
            catch (OperationCanceledException)
            {
                _logger.LogWarning($"[KeaStatsService] Timeout of 3s exceeded querying '{statName}' from Kea control socket.");
            }
            catch (Exception ex)
            {
                _logger.LogWarning($"[KeaStatsService] Socket communication failure for '{statName}': {ex.Message}");
            }
            return null;
        }
    }
}
