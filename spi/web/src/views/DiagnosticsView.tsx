import React, { useState, useEffect } from 'react';
import { apiFetch } from '../utils/api';
import { Database, Search, RefreshCw, Layers, ShieldAlert, Clock, User, Calendar, ArrowRight, ShieldCheck } from 'lucide-react';

interface LeaseInfo {
  ipAddress: string;
  macAddress: string;
  validLifetime: number;
  expire: string | null;
  state: string;
  stateId: number;
}

interface HostInfo {
  id: number;
  macAddress: string;
  identifierType: number;
  ipAddress: string;
  hostname: string | null;
  clase: string | null;
  tipoDispositivo: string | null;
}

interface IpHistoryInfo {
  id: number;
  ipAddress: string;
  macAddress: string;
  fechaDesde: string;
  fechaHasta: string | null;
  cliente: string;
}

interface HardwareHistoryInfo {
  id: number;
  macAddress: string;
  modelo: string;
  cliente: string;
  fechaEntrega: string;
  fechaDevolucion: string | null;
  motivoCambio: string;
  operador: string;
}

interface DiagnosticsViewProps {
  showToast: (message: string, type?: 'success' | 'error' | 'info') => void;
}

export const DiagnosticsView: React.FC<DiagnosticsViewProps> = ({ showToast }) => {
  const [activeTab, setActiveTab] = useState<'leases' | 'hosts' | 'history'>('leases');
  const [leases, setLeases] = useState<LeaseInfo[]>([]);
  const [hosts, setHosts] = useState<HostInfo[]>([]);
  const [ipHistory, setIpHistory] = useState<IpHistoryInfo[]>([]);
  const [hwHistory, setHardwareHistory] = useState<HardwareHistoryInfo[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [filterText, setFilterText] = useState<string>('');
  const [historyQuery, setHistoryQuery] = useState<string>('');

  const loadData = async () => {
    setLoading(true);
    try {
      if (activeTab === 'leases') {
        const res = await apiFetch<LeaseInfo[]>('/api/diagnostics/leases');
        if (res.success && res.data) {
          setLeases(res.data);
        } else {
          showToast(res.error || 'No se pudieron cargar los leases.', 'error');
        }
      } else if (activeTab === 'hosts') {
        const res = await apiFetch<HostInfo[]>('/api/diagnostics/hosts');
        if (res.success && res.data) {
          setHosts(res.data);
        } else {
          showToast(res.error || 'No se pudieron cargar las reservas estáticas.', 'error');
        }
      } else {
        // Consultar los historiales de auditoría en paralelo
        const [ipRes, hwRes] = await Promise.all([
          apiFetch<IpHistoryInfo[]>(`/api/diagnostics/history/ip?query=${encodeURIComponent(historyQuery)}`),
          apiFetch<HardwareHistoryInfo[]>(`/api/diagnostics/history/hardware?query=${encodeURIComponent(historyQuery)}`)
        ]);

        if (ipRes.success && ipRes.data) {
          setIpHistory(ipRes.data);
        }
        if (hwRes.success && hwRes.data) {
          setHardwareHistory(hwRes.data);
        }
        if (!ipRes.success || !hwRes.success) {
          showToast('Ocurrió un inconveniente al resolver algunos de los historiales de auditoría.', 'info');
        }
      }
    } catch (err: any) {
      showToast(err.message || 'Error de conexión con el servidor.', 'error');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, [activeTab]);

  const handleHistorySearch = (e: React.FormEvent) => {
    e.preventDefault();
    loadData();
  };

  // Filtrado del lado del cliente para búsquedas instantáneas
  const filteredLeases = leases.filter(l => 
    (l.ipAddress?.toLowerCase() || '').includes(filterText.toLowerCase()) ||
    (l.macAddress?.toLowerCase() || '').includes(filterText.toLowerCase()) ||
    (l.state?.toLowerCase() || '').includes(filterText.toLowerCase())
  );

  const filteredHosts = hosts.filter(h => 
    (h.ipAddress?.toLowerCase() || '').includes(filterText.toLowerCase()) ||
    (h.macAddress?.toLowerCase() || '').includes(filterText.toLowerCase()) ||
    (h.clase?.toLowerCase() || '').includes(filterText.toLowerCase()) ||
    (h.tipoDispositivo?.toLowerCase() || '').includes(filterText.toLowerCase())
  );

  const getRelativeTime = (expireStr: string | null) => {
    if (!expireStr) return 'N/A';
    const expireDate = new Date(expireStr);
    const now = new Date();
    const diffMs = expireDate.getTime() - now.getTime();
    
    if (diffMs < 0) {
      return 'Expirado';
    }

    const diffMins = Math.floor(diffMs / 60000);
    if (diffMins < 60) {
      return `Quedan ${diffMins} min`;
    }

    const diffHours = Math.floor(diffMins / 60);
    const remainingMins = diffMins % 60;
    return `Quedan ${diffHours}h ${remainingMins}m`;
  };

  return (
    <div className="view-container animate-fade-in" style={{ padding: '20px' }}>
      {/* Encabezado Principal */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
        <div>
          <h1 style={{ display: 'flex', alignItems: 'center', gap: '8px', margin: 0, fontSize: '20px', fontWeight: 700 }}>
            <Database size={24} style={{ color: 'var(--border-active)' }} />
            Consola de Diagnóstico Kea DHCP
          </h1>
          <p style={{ margin: '4px 0 0 0', color: 'var(--text-muted)', fontSize: '12px' }}>
            🔧 Entorno de desarrollo para explorar asignaciones dinámicas, reservas estáticas y trazas de auditoría.
          </p>
        </div>
        <button 
          onClick={loadData} 
          disabled={loading} 
          className="btn btn-secondary" 
          style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px' }}
        >
          <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
          Actualizar Datos
        </button>
      </div>

      {/* Alerta de Consola Privada */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: '12px',
        padding: '12px 16px',
        backgroundColor: 'rgba(230, 242, 233, 0.5)',
        borderLeft: '4px solid var(--border-active)',
        marginBottom: '20px',
        borderRadius: '0px'
      }}>
        <ShieldAlert size={18} style={{ color: 'var(--border-active)' }} />
        <span style={{ fontSize: '12px', fontWeight: 500, color: 'var(--text-muted)' }}>
          Esta vista es confidencial y restringida únicamente para operadores con rango de <strong>ADMINISTRADOR</strong>. No es visible para operadores tradicionales de atención al cliente.
        </span>
      </div>

      {/* Tabs y Caja de Filtro */}
      <div style={{ 
        display: 'flex', 
        justifyContent: 'space-between', 
        alignItems: 'center', 
        gap: '16px', 
        marginBottom: '16px',
        flexWrap: 'wrap'
      }}>
        <div style={{ display: 'flex', gap: '8px' }}>
          <button
            onClick={() => { setActiveTab('leases'); setFilterText(''); }}
            className={`btn ${activeTab === 'leases' ? 'btn-primary' : 'btn-secondary'}`}
            style={{ fontSize: '12px', padding: '8px 16px' }}
          >
            Leases DHCP Activos (lease4)
          </button>
          <button
            onClick={() => { setActiveTab('hosts'); setFilterText(''); }}
            className={`btn ${activeTab === 'hosts' ? 'btn-primary' : 'btn-secondary'}`}
            style={{ fontSize: '12px', padding: '8px 16px' }}
          >
            Reservas de Red (hosts)
          </button>
          <button
            onClick={() => { setActiveTab('history'); setFilterText(''); }}
            className={`btn ${activeTab === 'history' ? 'btn-primary' : 'btn-secondary'}`}
            style={{ fontSize: '12px', padding: '8px 16px' }}
          >
            🔍 Auditoría e Historiales
          </button>
        </div>

        {activeTab !== 'history' && (
          <div style={{ position: 'relative', minWidth: '280px' }}>
            <Search size={16} style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', opacity: 0.5 }} />
            <input
              type="text"
              placeholder="Buscar en la tabla..."
              value={filterText}
              onChange={(e) => setFilterText(e.target.value)}
              style={{
                paddingLeft: '32px',
                width: '100%',
                fontSize: '12px',
                height: '36px'
              }}
            />
          </div>
        )}
      </div>

      {/* Tab de HISTORIAL DE AUDITORÍA (TIMELINE) */}
      {activeTab === 'history' && (
        <div style={{ marginBottom: '24px' }} className="card">
          <form onSubmit={handleHistorySearch} style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
            <div style={{ flex: 1, position: 'relative' }}>
              <Search size={16} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', opacity: 0.5 }} />
              <input
                type="text"
                placeholder="Ingresa IP, MAC o Razón Social del Cliente para auditar su historial completo..."
                value={historyQuery}
                onChange={(e) => setHistoryQuery(e.target.value)}
                style={{ paddingLeft: '38px', width: '100%', height: '40px', fontSize: '13px' }}
              />
            </div>
            <button type="submit" disabled={loading} className="btn btn-primary" style={{ height: '40px', padding: '0 24px', fontSize: '13px' }}>
              Buscar Auditoría
            </button>
          </form>
          <p style={{ margin: '8px 0 0 0', fontSize: '11px', color: 'var(--text-muted)' }}>
            💡 Este portal consulta los registros inmutables históricos generados en caliente por los disparadores transaccionales de Postgres.
          </p>
        </div>
      )}

      {/* Contenedor Principal de Datos (Panel Blanco) */}
      <div className="card" style={{ padding: '0px', overflow: 'hidden', border: '1px solid var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        {/* Sub-Header con estadísticas rápidas */}
        <div style={{ 
          padding: '12px 16px', 
          borderBottom: '1px solid var(--border-color)', 
          backgroundColor: 'var(--bg-tertiary)',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center'
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '11px', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.5px' }}>
            <Layers size={13} />
            {activeTab === 'leases' ? 'Concesiones IPv4 Activas de Kea' : activeTab === 'hosts' ? 'Reservas Fijas DHCP Sincronizadas' : 'Consola de Trazabilidad e Historial ISP'}
          </div>
          <div style={{ fontSize: '11px', fontWeight: 500, color: 'var(--text-muted)' }}>
            {activeTab === 'leases' && `Coincidencias: ${filteredLeases.length} / Total: ${leases.length}`}
            {activeTab === 'hosts' && `Coincidencias: ${filteredHosts.length} / Total: ${hosts.length}`}
            {activeTab === 'history' && `Resultados: ${ipHistory.length + hwHistory.length} registros`}
          </div>
        </div>

        {loading ? (
          <div style={{ padding: '80px 0', textAlign: 'center' }}>
            <div className="animate-spin" style={{ 
              width: '32px', 
              height: '32px', 
              border: '3px solid var(--border-color)', 
              borderTopColor: 'var(--border-active)', 
              borderRadius: '50%',
              margin: '0 auto 12px auto'
            }}></div>
            <p style={{ color: 'var(--text-muted)', fontSize: '12px' }}>Consultando esquemas de auditoría en Postgres...</p>
          </div>
        ) : activeTab === 'leases' ? (
          /* Tabla de LEASES */
          filteredLeases.length === 0 ? (
            <div style={{ padding: '60px 20px', textAlign: 'center', color: 'var(--text-muted)' }}>
              No hay concesiones DHCP dinámicas registradas en este momento.
            </div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '12px' }}>
                <thead>
                  <tr style={{ backgroundColor: 'var(--bg-tertiary)', borderBottom: '1px solid var(--border-color)' }}>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>Dirección IP</th>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>Hardware MAC</th>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>Tiempo Alquiler</th>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>Fecha Expiración</th>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>Restante</th>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>Estado Kea</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredLeases.map((l, index) => {
                    const isExpired = l.expire ? new Date(l.expire).getTime() < Date.now() : false;
                    return (
                      <tr key={index} style={{ borderBottom: '1px solid var(--border-color)', transition: 'background 0.1s' }} className="table-row">
                        <td style={{ padding: '12px 16px' }}>
                          <code style={{ fontSize: '12px', fontWeight: 600, color: 'var(--border-active)' }}>{l.ipAddress}</code>
                        </td>
                        <td style={{ padding: '12px 16px' }}>
                          <code style={{ fontSize: '12px' }}>{l.macAddress}</code>
                        </td>
                        <td style={{ padding: '12px 16px', color: 'var(--text-muted)' }}>
                          {l.validLifetime} seg
                        </td>
                        <td style={{ padding: '12px 16px', color: 'var(--text-muted)' }}>
                          {l.expire ? new Date(l.expire).toLocaleString() : 'Infinito'}
                        </td>
                        <td style={{ padding: '12px 16px', fontWeight: 500, color: isExpired ? '#ef4444' : 'var(--text-main)' }}>
                          {getRelativeTime(l.expire)}
                        </td>
                        <td style={{ padding: '12px 16px' }}>
                          <span style={{ 
                            fontSize: '11px', 
                            padding: '3px 8px', 
                            borderRadius: '4px',
                            fontWeight: 600,
                            backgroundColor: isExpired ? '#fee2e2' : 'rgba(230, 242, 233, 0.8)',
                            color: isExpired ? '#ef4444' : '#2e6b3b'
                          }}>
                            {isExpired ? 'Expirado (Reclaimed)' : l.state}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )
        ) : activeTab === 'hosts' ? (
          /* Tabla de HOST RESERVATIONS */
          filteredHosts.length === 0 ? (
            <div style={{ padding: '60px 20px', textAlign: 'center', color: 'var(--text-muted)' }}>
              No hay reservas estáticas de red creadas en este momento.
            </div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '12px' }}>
                <thead>
                  <tr style={{ backgroundColor: 'var(--bg-tertiary)', borderBottom: '1px solid var(--border-color)' }}>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>host_id</th>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>mac_en_hex</th>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>tipo</th>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>ip_reservada</th>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>clase</th>
                    <th style={{ padding: '12px 16px', fontWeight: 600 }}>tipo_dispositivo</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredHosts.map((h, index) => (
                    <tr key={index} style={{ borderBottom: '1px solid var(--border-color)' }} className="table-row">
                      <td style={{ padding: '12px 16px', color: 'var(--text-muted)' }}>{h.id}</td>
                      <td style={{ padding: '12px 16px' }}>
                        <code style={{ fontSize: '12px' }}>{h.macAddress}</code>
                      </td>
                      <td style={{ padding: '12px 16px', color: 'var(--text-muted)' }}>
                        {h.identifierType}
                      </td>
                      <td style={{ padding: '12px 16px' }}>
                        <code style={{ fontSize: '12px', fontWeight: 600, color: 'var(--border-active)' }}>
                          {h.ipAddress || '—'}
                        </code>
                      </td>
                      <td style={{ padding: '12px 16px' }}>
                        <span style={{ 
                          fontSize: '11px', 
                          padding: '3px 8px', 
                          borderRadius: '4px',
                          fontWeight: 500,
                          backgroundColor: 'var(--bg-tertiary)',
                          color: 'var(--text-muted)',
                          border: '1px solid var(--border-color)'
                        }}>
                          {h.clase || '—'}
                        </span>
                      </td>
                      <td style={{ padding: '12px 16px' }}>
                        <span style={{ 
                          fontSize: '11px', 
                          padding: '3px 8px', 
                          borderRadius: '4px',
                          fontWeight: 600,
                          backgroundColor: h.tipoDispositivo === 'Cablemodem' ? 'rgba(230, 242, 233, 0.8)' : '#fef08a',
                          color: h.tipoDispositivo === 'Cablemodem' ? '#2e6b3b' : '#a16207'
                        }}>
                          {h.tipoDispositivo || '—'}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )
        ) : (
          /* VISTA DE AUDITORÍA / HISTORIAL SPLIT PANEL */
          <div style={{ padding: '24px', backgroundColor: 'var(--bg-tertiary)' }}>
            {ipHistory.length === 0 && hwHistory.length === 0 ? (
              !historyQuery ? (
                <div style={{ padding: '40px 20px', textAlign: 'center', color: 'var(--text-muted)' }}>
                  <Clock size={36} style={{ display: 'block', margin: '0 auto 12px auto', opacity: 0.5 }} />
                  No hay registros de auditoría registrados aún en la base de datos de red o inventario.
                  <span style={{ display: 'block', fontSize: '11px', marginTop: '6px', opacity: 0.7 }}>
                    💡 Los historiales se generan automáticamente cuando Kea asigna leases o se realizan recambios de equipamiento.
                  </span>
                </div>
              ) : (
                <div style={{ padding: '40px 20px', textAlign: 'center', color: 'var(--text-muted)' }}>
                  No se encontraron registros de auditoría que coincidan con "{historyQuery}" en las bases de datos de red o inventario.
                </div>
              )
            ) : (
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(400px, 1fr))', gap: '24px' }}>
                
                {/* COLUMNA 1: HISTORIAL DE IPs */}
                <div style={{ display: 'flex', flexDirection: 'column' }}>
                  <h3 style={{ fontSize: '13px', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '16px', color: 'var(--text-main)', borderBottom: '2px solid var(--border-color)', paddingBottom: '8px' }}>
                    <Layers size={15} style={{ color: 'var(--border-active)' }} />
                    Línea de Tiempo: Historial de Concesiones e IPs
                  </h3>
                  
                  {ipHistory.length === 0 ? (
                    <div style={{ padding: '20px', backgroundColor: 'var(--bg-secondary)', border: '1px dashed var(--border-color)', borderRadius: '4px', fontSize: '12px', color: 'var(--text-muted)', textAlign: 'center' }}>
                      Sin concesiones dinámicas registradas para este criterio de búsqueda.
                    </div>
                  ) : (
                    <div style={{ position: 'relative', paddingLeft: '20px', borderLeft: '2px solid var(--border-color)' }}>
                      {ipHistory.map((item) => (
                        <div key={item.id} style={{ position: 'relative', marginBottom: '20px' }}>
                          {/* Nodo de la línea de tiempo */}
                          <div style={{ 
                            position: 'absolute', 
                            left: '-26px', 
                            top: '2px', 
                            width: '10px', 
                            height: '10px', 
                            borderRadius: '50%', 
                            backgroundColor: item.fechaHasta ? 'var(--border-color)' : 'var(--border-active)', 
                            border: '2px solid var(--bg-secondary)' 
                          }} />
                          
                          <div className="card" style={{ padding: '12px 16px', backgroundColor: 'var(--bg-secondary)', border: '1px solid var(--border-color)', boxShadow: '0 1px 3px rgba(0,0,0,0.02)' }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                              <code style={{ fontSize: '13px', fontWeight: 700, color: 'var(--border-active)' }}>{item.ipAddress}</code>
                              <span style={{ 
                                fontSize: '10px', 
                                fontWeight: 600, 
                                padding: '2px 6px', 
                                borderRadius: '4px',
                                backgroundColor: item.fechaHasta ? 'var(--bg-tertiary)' : 'rgba(230, 242, 233, 0.8)',
                                color: item.fechaHasta ? 'var(--text-muted)' : '#2e6b3b'
                              }}>
                                {item.fechaHasta ? 'Lease Finalizado' : 'Lease Activo / En Uso'}
                              </span>
                            </div>
                            
                            <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', fontSize: '11px', color: 'var(--text-muted)' }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                                <User size={12} />
                                <span>Abonado: <strong style={{ color: 'var(--text-main)' }}>{item.cliente}</strong></span>
                              </div>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                                <Database size={12} />
                                <span>MAC: <strong style={{ color: 'var(--text-main)' }}>{item.macAddress}</strong></span>
                              </div>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginTop: '4px', borderTop: '1px solid var(--border-color)', paddingTop: '4px' }}>
                                <Calendar size={12} />
                                <span>{new Date(item.fechaDesde).toLocaleString()}</span>
                                <ArrowRight size={10} />
                                <span>{item.fechaHasta ? new Date(item.fechaHasta).toLocaleString() : 'En curso'}</span>
                              </div>
                            </div>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                {/* COLUMNA 2: HISTORIAL DE CUSTODIA DE EQUIPO */}
                <div style={{ display: 'flex', flexDirection: 'column' }}>
                  <h3 style={{ fontSize: '13px', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '16px', color: 'var(--text-main)', borderBottom: '2px solid var(--border-color)', paddingBottom: '8px' }}>
                    <ShieldCheck size={15} style={{ color: '#059669' }} />
                    Línea de Tiempo: Ciclo de Vida del Hardware
                  </h3>

                  {hwHistory.length === 0 ? (
                    <div style={{ padding: '20px', backgroundColor: 'var(--bg-secondary)', border: '1px dashed var(--border-color)', borderRadius: '4px', fontSize: '12px', color: 'var(--text-muted)', textAlign: 'center' }}>
                      Sin hitos de recambio de equipamiento o custodia de stock registrados.
                    </div>
                  ) : (
                    <div style={{ position: 'relative', paddingLeft: '20px', borderLeft: '2px solid var(--border-color)' }}>
                      {hwHistory.map((item) => (
                        <div key={item.id} style={{ position: 'relative', marginBottom: '20px' }}>
                          {/* Nodo de la línea de tiempo */}
                          <div style={{ 
                            position: 'absolute', 
                            left: '-26px', 
                            top: '2px', 
                            width: '10px', 
                            height: '10px', 
                            borderRadius: '50%', 
                            backgroundColor: item.fechaDevolucion ? '#cbd5e1' : '#059669', 
                            border: '2px solid var(--bg-secondary)' 
                          }} />

                          <div className="card" style={{ padding: '12px 16px', backgroundColor: 'var(--bg-secondary)', border: '1px solid var(--border-color)', boxShadow: '0 1px 3px rgba(0,0,0,0.02)' }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                              <strong style={{ fontSize: '12px', color: 'var(--text-main)' }}>{item.motivoCambio}</strong>
                              <span style={{ 
                                fontSize: '10px', 
                                fontWeight: 600, 
                                padding: '2px 6px', 
                                borderRadius: '4px',
                                backgroundColor: item.fechaDevolucion ? '#f1f5f9' : '#d1fae5',
                                color: item.fechaDevolucion ? '#64748b' : '#065f46'
                              }}>
                                {item.fechaDevolucion ? 'Devuelto a Stock' : 'Activo en Domicilio'}
                              </span>
                            </div>

                            <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', fontSize: '11px', color: 'var(--text-muted)' }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                                <User size={12} />
                                <span>Custodio: <strong style={{ color: 'var(--text-main)' }}>{item.cliente}</strong></span>
                              </div>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                                <Database size={12} />
                                <span>Equipo MAC: <strong style={{ color: 'var(--text-main)' }}>{item.macAddress}</strong> <span style={{ opacity: 0.7 }}>({item.modelo})</span></span>
                              </div>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                                <ShieldCheck size={12} style={{ color: 'var(--border-active)' }} />
                                <span>Autorizado por: <strong style={{ color: 'var(--text-main)' }}>{item.operador}</strong></span>
                              </div>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginTop: '4px', borderTop: '1px solid var(--border-color)', paddingTop: '4px' }}>
                                <Calendar size={12} />
                                <span>Entregado: {new Date(item.fechaEntrega).toLocaleString()}</span>
                                {item.fechaDevolucion && (
                                  <>
                                    <ArrowRight size={10} />
                                    <span>Devuelto: {new Date(item.fechaDevolucion).toLocaleString()}</span>
                                  </>
                                )}
                              </div>
                            </div>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
