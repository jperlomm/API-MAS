import React, { useState, useEffect } from 'react';
import { RefreshCw, Users, Database, Activity, ToggleLeft, ShieldAlert, Zap, AlertTriangle, CheckCircle, WifiOff, BarChart2 } from 'lucide-react';
import { apiFetch, DashboardKpis, getDhcpHistory, DhcpHistoryEntry } from '../utils/api';

interface DashboardViewProps {
  showToast: (msg: string, type: 'success' | 'error') => void;
}

export const DashboardView: React.FC<DashboardViewProps> = ({ showToast }) => {
  const [kpis, setKpis] = useState<DashboardKpis | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [history, setHistory] = useState<DhcpHistoryEntry[]>([]);
  const [historyLoading, setHistoryLoading] = useState<boolean>(true);
  const [hoveredIndex, setHoveredIndex] = useState<number | null>(null);

  const fetchKpis = async () => {
    const res = await apiFetch<DashboardKpis>('/api/dashboard/kpis');
    if (res.success && res.data) {
      setKpis(res.data);
    } else {
      showToast(res.error || 'No se pudieron cargar las métricas.', 'error');
    }
    setLoading(false);
  };

  const fetchHistory = async () => {
    setHistoryLoading(true);
    const res = await getDhcpHistory();
    if (res.success && res.data) {
      setHistory(res.data);
    }
    setHistoryLoading(false);
  };

  const manualRefresh = async () => {
    setLoading(true);
    await Promise.all([fetchKpis(), fetchHistory()]);
  };

  useEffect(() => {
    fetchKpis();
    fetchHistory();

    const interval = setInterval(() => {
      fetchKpis();
    }, 20000);

    const historyInterval = setInterval(() => {
      fetchHistory();
    }, 120000);

    return () => {
      clearInterval(interval);
      clearInterval(historyInterval);
    };
  }, []);

  const monitor = kpis?.dhcpMonitor;
  const keaAvailable = monitor?.keaAvailable ?? false;
  const rates = monitor?.rates;

  // -------------------------------------------------------------------------
  // NOC STATUS LOGIC
  // -------------------------------------------------------------------------
  let statusColor = 'var(--success)';
  let statusBg = 'rgba(16, 185, 129, 0.05)';
  let statusBorder = 'rgba(16, 185, 129, 0.15)';
  let statusLabel = 'SANO (Estable)';
  let StatusIcon = CheckCircle;
  let isFlashing = false;

  const totalPacketsMin = rates 
    ? (rates.discoverPerMin ?? 0) + (rates.requestPerMin ?? 0)
    : 0;

  if (!keaAvailable) {
    statusColor = 'var(--danger)';
    statusBg = 'rgba(239, 68, 68, 0.05)';
    statusBorder = 'rgba(239, 68, 68, 0.2)';
    statusLabel = 'MONITOR OFFLINE';
    StatusIcon = WifiOff;
  } else if (totalPacketsMin > 300 || (rates?.dropPerMin ?? 0) > 10) {
    statusColor = 'var(--danger)';
    statusBg = 'rgba(239, 68, 68, 0.08)';
    statusBorder = 'rgba(239, 68, 68, 0.25)';
    statusLabel = 'TORMENTA DHCP DETECTADA';
    StatusIcon = ShieldAlert;
    isFlashing = true;
  } else if (totalPacketsMin > 100 || (rates?.nakPerMin ?? 0) > 5) {
    statusColor = 'var(--warning)';
    statusBg = 'rgba(245, 158, 11, 0.05)';
    statusBorder = 'rgba(245, 158, 11, 0.18)';
    statusLabel = 'ALTA DEMANDA RECIENTE';
    StatusIcon = AlertTriangle;
  }

  return (
    <div style={{ animation: 'fadeIn 0.4s ease-out' }}>
      {/* HEADER BAR */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
        <div 
          style={{ 
            display: 'flex', 
            gap: '10px', 
            alignItems: 'center',
            padding: '8px 16px',
            backgroundColor: statusBg,
            border: `1px solid ${statusBorder}`,
            borderRadius: '24px',
            boxShadow: isFlashing ? `0 0 12px ${statusColor}40` : 'none',
            transition: 'all 0.4s ease'
          }}
        >
          <StatusIcon 
            size={16} 
            style={{ 
              color: statusColor, 
              animation: isFlashing ? 'pulse 1s infinite alternate' : 'none' 
            }} 
          />
          <span style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-main)', letterSpacing: '0.3px' }}>
            NOC Live: <span style={{ color: statusColor }}>{statusLabel}</span>
          </span>
        </div>
        
        <button 
          onClick={manualRefresh} 
          className="btn btn-secondary" 
          style={{ display: 'flex', gap: '8px', alignItems: 'center', padding: '10px 18px', fontSize: '13px' }}
          disabled={loading}
        >
          <RefreshCw size={14} className={loading ? 'spin' : ''} style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} />
          Actualizar Métricas
        </button>
      </div>

      {/* KPI CARDS GRID */}
      <div className="metrics-grid" style={{ marginBottom: '28px' }}>
        <div className="metric-card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div>
              <div className="metric-title">Abonados Registrados</div>
              <div className="metric-value">{loading && !kpis ? '...' : kpis?.clientesTotal ?? 0}</div>
            </div>
            <div style={{ padding: '8px', borderRadius: '8px', backgroundColor: 'rgba(59, 130, 246, 0.08)' }}>
              <Users size={22} style={{ color: 'var(--accent-blue)' }} />
            </div>
          </div>
        </div>

        <div className="metric-card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div>
              <div className="metric-title">Equipos en Stock</div>
              <div className="metric-value">{loading && !kpis ? '...' : kpis?.equiposStock ?? 0}</div>
            </div>
            <div style={{ padding: '8px', borderRadius: '8px', backgroundColor: 'rgba(245, 158, 11, 0.08)' }}>
              <Database size={22} style={{ color: 'var(--warning)' }} />
            </div>
          </div>
        </div>

        <div className="metric-card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div>
              <div className="metric-title">Equipos Activos (Modem/ONU)</div>
              <div className="metric-value">{loading && !kpis ? '...' : kpis?.equiposActivos ?? 0}</div>
            </div>
            <div style={{ padding: '8px', borderRadius: '8px', backgroundColor: 'rgba(16, 185, 129, 0.08)' }}>
              <Activity size={22} style={{ color: 'var(--success)' }} />
            </div>
          </div>
        </div>

        <div className="metric-card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div>
              <div className="metric-title">Servicios Suspendidos</div>
              <div className="metric-value" style={{ color: 'var(--danger)' }}>
                {loading && !kpis ? '...' : kpis?.serviciosSuspendidos ?? 0}
              </div>
            </div>
            <div style={{ padding: '8px', borderRadius: '8px', backgroundColor: 'rgba(239, 68, 68, 0.08)' }}>
              <ToggleLeft size={22} style={{ color: 'var(--danger)' }} />
            </div>
          </div>
        </div>
      </div>

      {/* PRAGMATIC NOC DHCP OBSERVAN OPERATOR PANEL */}
      <div 
        className="panel" 
        style={{ 
          border: isFlashing ? '1px solid rgba(239, 68, 68, 0.4)' : undefined, 
          boxShadow: isFlashing ? '0 4px 20px rgba(239, 68, 68, 0.04)' : undefined,
          transition: 'all 0.3s ease'
        }}
      >
        <div className="panel-header" style={{ borderBottom: '1px solid var(--border-color)', paddingBottom: '16px', marginBottom: '20px' }}>
          <div className="panel-title" style={{ display: 'flex', gap: '8px', alignItems: 'center', fontSize: '15px', fontWeight: 600 }}>
            <Zap size={18} style={{ color: isFlashing ? 'var(--danger)' : 'var(--accent)' }} />
            Monitoreo de Aprovisionamiento DHCP (RAM Socket)
          </div>
        </div>

        {!keaAvailable ? (
          /* OFFLINE STATUS WIDGET */
          <div 
            style={{ 
              display: 'flex', 
              flexDirection: 'column', 
              alignItems: 'center', 
              justifyContent: 'center', 
              padding: '40px 20px', 
              backgroundColor: 'rgba(239, 68, 68, 0.02)', 
              border: '1px dashed rgba(239, 68, 68, 0.15)', 
              borderRadius: '8px',
              textAlign: 'center'
            }}
          >
            <WifiOff size={40} style={{ color: 'var(--danger)', marginBottom: '16px', opacity: 0.8 }} />
            <h4 style={{ margin: '0 0 8px 0', fontSize: '15px', color: 'var(--text-main)', fontWeight: 600 }}>🔴 KEA MONITOR OFFLINE</h4>
            <p style={{ margin: 0, fontSize: '13px', color: 'var(--text-muted)', maxWidth: '420px', lineHeight: 1.5 }}>
              No se pudo establecer conexión con el socket de control de Kea DHCP en <code style={{ color: 'var(--danger)' }}>/var/run/kea</code>. 
              El servidor podría estar temporalmente detenido o los permisos del volumen están desalineados. El aprovisionamiento de red permanece aislado y protegido.
            </p>
          </div>
        ) : (
          /* LIVE TELEMETRY DASHBOARD Grid (Three Observability Levels) */
          <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
            
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '16px' }}>
              
               {/* LEVEL 1 — DEMANDA (INGRESANTE) */}
              <div style={{ backgroundColor: 'var(--bg-primary)', padding: '16px', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
                <div style={{ fontSize: '11px', fontWeight: 700, color: 'var(--accent-blue)', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: '12px' }}>
                  Nivel 1: Demanda (Ingresante)
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '13px' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Solicitudes DISCOVER</span>
                    <span style={{ fontWeight: 600, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                      {rates?.discoverPerMin !== null ? (
                        <>
                          {rates?.discoverPerMin?.toFixed(1)} / min
                          <span style={{ fontSize: '10px', color: 'var(--text-muted)', backgroundColor: 'rgba(255,255,255,0.03)', padding: '1px 5px', borderRadius: '4px', border: '1px solid var(--border-color)' }}>
                            {monitor?.raw?.discoverTotal?.toLocaleString() ?? 0} tot
                          </span>
                        </>
                      ) : 'Cargando...'}
                    </span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '13px' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Asociaciones REQUEST</span>
                    <span style={{ fontWeight: 600, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                      {rates?.requestPerMin !== null ? (
                        <>
                          {rates?.requestPerMin?.toFixed(1)} / min
                          <span style={{ fontSize: '10px', color: 'var(--text-muted)', backgroundColor: 'rgba(255,255,255,0.03)', padding: '1px 5px', borderRadius: '4px', border: '1px solid var(--border-color)' }}>
                            {monitor?.raw?.requestTotal?.toLocaleString() ?? 0} tot
                          </span>
                        </>
                      ) : 'Cargando...'}
                    </span>
                  </div>
                </div>
              </div>

              {/* LEVEL 2 — CAPACIDAD (SALIENTE) */}
              <div style={{ backgroundColor: 'var(--bg-primary)', padding: '16px', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
                <div style={{ fontSize: '11px', fontWeight: 700, color: 'var(--success)', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: '12px' }}>
                  Nivel 2: Capacidad (Saliente)
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '13px' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Asignados ACK</span>
                    <span style={{ fontWeight: 600, color: 'var(--success)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                      {rates?.ackPerMin !== null ? (
                        <>
                          {rates?.ackPerMin?.toFixed(1)} / min
                          <span style={{ fontSize: '10px', color: 'var(--text-muted)', backgroundColor: 'rgba(255,255,255,0.03)', padding: '1px 5px', borderRadius: '4px', border: '1px solid var(--border-color)' }}>
                            {monitor?.raw?.ackTotal?.toLocaleString() ?? 0} tot
                          </span>
                        </>
                      ) : 'Cargando...'}
                    </span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '13px' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Rechazados NAK</span>
                    <span style={{ fontWeight: 600, color: rates?.nakPerMin && rates.nakPerMin > 0 ? 'var(--warning)' : 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                      {rates?.nakPerMin !== null ? (
                        <>
                          {rates?.nakPerMin?.toFixed(1)} / min
                          <span style={{ fontSize: '10px', color: 'var(--text-muted)', backgroundColor: 'rgba(255,255,255,0.03)', padding: '1px 5px', borderRadius: '4px', border: '1px solid var(--border-color)' }}>
                            {monitor?.raw?.nakTotal?.toLocaleString() ?? 0} tot
                          </span>
                        </>
                      ) : 'Cargando...'}
                    </span>
                  </div>
                </div>
              </div>

              {/* LEVEL 3 — PROBLEMAS (DROPS) */}
              <div style={{ backgroundColor: 'var(--bg-primary)', padding: '16px', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
                <div style={{ fontSize: '11px', fontWeight: 700, color: 'var(--danger)', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: '12px' }}>
                  Nivel 3: Descartes / Caídas
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '13px' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Paquetes DROPPED</span>
                    <span style={{ fontWeight: 600, color: rates?.dropPerMin && rates.dropPerMin > 0 ? 'var(--danger)' : 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                      {rates?.dropPerMin !== null ? (
                        <>
                          {rates?.dropPerMin?.toFixed(1)} / min
                          <span style={{ fontSize: '10px', color: 'var(--text-muted)', backgroundColor: 'rgba(255,255,255,0.03)', padding: '1px 5px', borderRadius: '4px', border: '1px solid var(--border-color)' }}>
                            {monitor?.raw?.dropTotal?.toLocaleString() ?? 0} tot
                          </span>
                        </>
                      ) : 'Cargando...'}
                    </span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '13px' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Frecuencia de Polling</span>
                    <span style={{ fontWeight: 500, color: 'var(--text-muted)' }}>Cada 30 segundos</span>
                  </div>
                </div>
              </div>

            </div>

            {/* ACK / REQUEST COMPLETION RATIO GAUGING CARD */}
            <div style={{ backgroundColor: 'var(--bg-primary)', padding: '18px', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                <div style={{ display: 'flex', flexDirection: 'column' }}>
                  <span style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-main)' }}>Relación Operativa: ACK / REQUEST</span>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Porcentaje de solicitudes REQUEST que recibieron asignación exitosa</span>
                </div>
                <span 
                  style={{ 
                    fontSize: '18px', 
                    fontWeight: 700, 
                    color: typeof monitor?.ackRequestRatio === 'number' 
                      ? (monitor.ackRequestRatio >= 95 ? 'var(--success)' : 'var(--warning)')
                      : 'var(--text-muted)' 
                  }}
                >
                  {typeof monitor?.ackRequestRatio === 'number' ? `${monitor.ackRequestRatio.toFixed(1)} %` : 'Calculando...'}
                </span>
              </div>
              
              {/* Beautiful custom styled HTML5 progress meter */}
              <div style={{ width: '100%', height: '8px', backgroundColor: 'rgba(255,255,255,0.05)', borderRadius: '4px', overflow: 'hidden' }}>
                <div 
                  style={{ 
                    width: `${typeof monitor?.ackRequestRatio === 'number' ? monitor.ackRequestRatio : 0}%`, 
                    height: '100%', 
                    backgroundColor: (monitor?.ackRequestRatio ?? 0) >= 95 ? 'var(--success)' : 'var(--warning)', 
                    transition: 'width 0.8s ease-out',
                    borderRadius: '4px'
                  }} 
                />
              </div>
            </div>

            {isFlashing && (
              <div 
                style={{ 
                  backgroundColor: 'rgba(239, 68, 68, 0.05)', 
                  border: '1px solid rgba(239, 68, 68, 0.2)', 
                  borderRadius: '6px', 
                  padding: '12px 16px', 
                  color: 'var(--text-main)',
                  fontSize: '13px',
                  lineHeight: '1.5',
                  display: 'flex',
                  gap: '12px',
                  alignItems: 'center'
                }}
              >
                <ShieldAlert size={20} style={{ color: 'var(--danger)', flexShrink: 0 }} />
                <div>
                  <strong>⚠️ Alerta de Avalancha DHCP:</strong> El volumen de tráfico entrante supera los límites de operación nominal. Esto sugiere de forma inequívoca el restablecimiento masivo de energía tras un corte de luz, o el reinicio abrupto de un nodo de distribución principal. Las tasas físicas de red se están regulando de forma segura y pasiva.
                </div>
              </div>
            )}

          </div>
        )}
      </div>

      {/* HISTORICAL DHCP TELEMETRY CHART PANEL */}
      {keaAvailable && (
        <div className="panel" style={{ marginTop: '24px' }}>
          <div className="panel-header" style={{ borderBottom: '1px solid var(--border-color)', paddingBottom: '16px', marginBottom: '20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px' }}>
            <div className="panel-title" style={{ display: 'flex', gap: '8px', alignItems: 'center', fontSize: '15px', fontWeight: 600 }}>
              <BarChart2 size={18} style={{ color: 'var(--accent-blue)' }} />
              Carga Histórica DHCP (Últimas 24 Horas)
            </div>
            
            {/* HOVER TOOLTIP / LEGEND HEADER */}
            <div style={{ fontSize: '13px', display: 'flex', gap: '12px', alignItems: 'center' }}>
              {hoveredIndex !== null && history[hoveredIndex] ? (
                <div style={{ display: 'flex', gap: '10px', alignItems: 'center', backgroundColor: 'rgba(255,255,255,0.03)', padding: '4px 12px', borderRadius: '16px', border: '1px solid var(--border-color)', animation: 'fadeIn 0.2s ease-out' }}>
                  <span style={{ fontWeight: 600, color: 'var(--text-main)' }}>
                    Slot {new Date(history[hoveredIndex].fecha).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}:
                  </span>
                  <span style={{ color: '#00b0ff' }}>DISCOVER: <strong>{history[hoveredIndex].discovers.toLocaleString()}</strong></span>
                  <span style={{ color: '#af00ff' }}>REQUEST: <strong>{history[hoveredIndex].requests.toLocaleString()}</strong></span>
                  <span style={{ color: '#00e676' }}>ACK: <strong>{history[hoveredIndex].acks.toLocaleString()}</strong></span>
                </div>
              ) : (
                <div style={{ display: 'flex', gap: '14px', color: 'var(--text-muted)' }}>
                  <span style={{ display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <span style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#00b0ff' }} /> DISCOVER
                  </span>
                  <span style={{ display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <span style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#af00ff' }} /> REQUEST
                  </span>
                  <span style={{ display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <span style={{ width: '8px', height: '8px', borderRadius: '50%', backgroundColor: '#00e676' }} /> ACK
                  </span>
                </div>
              )}
            </div>
          </div>

          {historyLoading ? (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '180px', color: 'var(--text-muted)', fontSize: '13px' }}>
              <RefreshCw size={24} className="spin" style={{ marginBottom: '12px', animation: 'spin 1.5s linear infinite' }} />
              Cargando historial de agregados...
            </div>
          ) : history.length === 0 ? (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '180px', color: 'var(--text-muted)', fontSize: '13px', border: '1px dashed var(--border-color)', borderRadius: '8px' }}>
              Aún no hay suficientes agregados guardados en Postgres (se genera la primera muestra al cumplirse la primera hora).
            </div>
          ) : (
            /* RESPONSIVE SVG GROUPED BAR CHART */
            <div style={{ position: 'relative', width: '100%', overflow: 'hidden' }}>
              <svg 
                viewBox="0 0 800 180" 
                style={{ width: '100%', height: 'auto', display: 'block', overflow: 'visible' }}
              >
                <defs>
                  <linearGradient id="discGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#00b0ff" stopOpacity="0.85" />
                    <stop offset="100%" stopColor="#0060df" stopOpacity="0.3" />
                  </linearGradient>
                  <linearGradient id="reqGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#af00ff" stopOpacity="0.85" />
                    <stop offset="100%" stopColor="#5f00bf" stopOpacity="0.3" />
                  </linearGradient>
                  <linearGradient id="ackGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#00e676" stopOpacity="0.85" />
                    <stop offset="100%" stopColor="#00a040" stopOpacity="0.3" />
                  </linearGradient>
                </defs>

                {/* HORIZONTAL GRID LINES & LABELS */}
                {(() => {
                  const maxVal = Math.max(...history.map(e => Math.max(e.discovers, e.requests, e.acks)), 10);
                  const ticks = [0, Math.round(maxVal / 2), maxVal];
                  const paddingLeft = 55;
                  const chartHeight = 120;
                  const paddingTop = 15;

                  return (
                    <>
                      {ticks.map((tick, index) => {
                        const y = paddingTop + chartHeight - (tick / maxVal) * chartHeight;
                        return (
                          <g key={index}>
                            <line 
                              x1={paddingLeft} 
                              y1={y} 
                              x2="790" 
                              y2={y} 
                              stroke="var(--border-color)" 
                              strokeWidth="1" 
                              strokeDasharray="4 6" 
                              opacity="0.3"
                            />
                            <text 
                              x={paddingLeft - 10} 
                              y={y + 4} 
                              fill="var(--text-muted)" 
                              fontSize="10" 
                              fontWeight="500"
                              textAnchor="end"
                            >
                              {tick >= 1000 ? `${(tick / 1000).toFixed(1)}k` : tick}
                            </text>
                          </g>
                        );
                      })}
                    </>
                  );
                })()}

                {/* GRAPH BARS & INTERACTION AREA */}
                {(() => {
                  const maxVal = Math.max(...history.map(e => Math.max(e.discovers, e.requests, e.acks)), 10);
                  const paddingLeft = 55;
                  const chartWidth = 735;
                  const chartHeight = 120;
                  const paddingTop = 15;
                  const colWidth = chartWidth / history.length;
                  const barWidth = Math.max(2, Math.min(8, colWidth / 4.5));

                  return history.map((entry, i) => {
                    const colX = paddingLeft + i * colWidth + (colWidth / 2);
                    const discHeight = (entry.discovers / maxVal) * chartHeight;
                    const reqHeight = (entry.requests / maxVal) * chartHeight;
                    const ackHeight = (entry.acks / maxVal) * chartHeight;
                    const baseY = paddingTop + chartHeight;

                    const isHovered = hoveredIndex === i;

                    return (
                      <g key={i}>
                        {/* Column Background Highlight on Hover */}
                        {isHovered && (
                          <rect 
                            x={paddingLeft + i * colWidth} 
                            y={paddingTop} 
                            width={colWidth} 
                            height={chartHeight} 
                            fill="rgba(255,255,255,0.02)" 
                            rx="4"
                          />
                        )}

                        {/* Discover Bar (Left) */}
                        <rect 
                          x={colX - barWidth * 1.5 - 2} 
                          y={baseY - discHeight} 
                          width={barWidth} 
                          height={discHeight} 
                          fill="url(#discGrad)" 
                          rx="2"
                          style={{ transition: 'all 0.3s ease' }}
                          opacity={hoveredIndex === null || isHovered ? 1 : 0.4}
                        />

                        {/* Request Bar (Middle) */}
                        <rect 
                          x={colX - barWidth / 2} 
                          y={baseY - reqHeight} 
                          width={barWidth} 
                          height={reqHeight} 
                          fill="url(#reqGrad)" 
                          rx="2"
                          style={{ transition: 'all 0.3s ease' }}
                          opacity={hoveredIndex === null || isHovered ? 1 : 0.4}
                        />

                        {/* Ack Bar (Right) */}
                        <rect 
                          x={colX + barWidth * 0.5 + 2} 
                          y={baseY - ackHeight} 
                          width={barWidth} 
                          height={ackHeight} 
                          fill="url(#ackGrad)" 
                          rx="2"
                          style={{ transition: 'all 0.3s ease' }}
                          opacity={hoveredIndex === null || isHovered ? 1 : 0.4}
                        />

                        {/* X-Axis Ticks (Label every 2nd col or 3rd col to avoid crowding) */}
                        {(history.length <= 12 || i % 2 === 0) && (
                          <text 
                            x={colX} 
                            y={baseY + 18} 
                            fill={isHovered ? 'var(--text-main)' : 'var(--text-muted)'} 
                            fontSize="10" 
                            fontWeight={isHovered ? '600' : '400'}
                            textAnchor="middle"
                          >
                            {(() => {
                              try {
                                const d = new Date(entry.fecha);
                                return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
                              } catch {
                                return '';
                              }
                            })()}
                          </text>
                        )}

                        {/* Large invisible interactive rect for Column Hover Detection */}
                        <rect 
                          x={paddingLeft + i * colWidth} 
                          y={paddingTop} 
                          width={colWidth} 
                          height={chartHeight + 25} 
                          fill="transparent" 
                          style={{ cursor: 'pointer' }}
                          onMouseEnter={() => setHoveredIndex(i)}
                          onMouseLeave={() => setHoveredIndex(null)}
                        />
                      </g>
                    );
                  });
                })()}

                {/* X-AXIS BASELINE */}
                <line 
                  x1="55" 
                  y1="135" 
                  x2="790" 
                  y2="135" 
                  stroke="var(--border-color)" 
                  strokeWidth="1.5" 
                />
              </svg>
            </div>
          )}
        </div>
      )}

      {/* FOOTER CORE DESCRIPTION */}
      <div className="panel" style={{ marginTop: '24px' }}>
        <div className="panel-header" style={{ marginBottom: '12px' }}>
          <div className="panel-title" style={{ fontSize: '14px', fontWeight: 600 }}>Estado del Núcleo DHCP</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '13px', lineHeight: '1.6', color: 'var(--text-muted)' }}>
          <p style={{ margin: 0 }}>
            El sistema de aprovisionamiento <strong>SPI-V1</strong> opera de forma desacoplada y directa sobre la base de datos de <strong>Kea DHCP</strong>.
          </p>
          <p style={{ margin: 0 }}>
            Cualquier cambio de suscripciones se refleja automáticamente en la tabla <code>public.hosts</code> mediante triggers nativos, forzando la inyección de leases sin interrupción del tráfico de telecomunicaciones.
          </p>
        </div>
      </div>
    </div>
  );
};

export default DashboardView;
