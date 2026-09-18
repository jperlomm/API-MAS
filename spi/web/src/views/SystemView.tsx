import React, { useState, useEffect } from 'react';
import { Server, Settings, Activity, RefreshCw, Play, CheckCircle2, AlertTriangle, Eye, EyeOff, Clock, ShieldAlert, Database, Globe, RotateCw, FileJson, Download, FolderArchive } from 'lucide-react';
import { apiFetch, getAccessToken } from '../utils/api';
import { useAuth } from '../context/AuthContext';

interface ServiceStatus {
  name: string;
  isUp: boolean;
  rawStatus: string;
  state: 'healthy' | 'starting' | 'unhealthy' | 'offline';
}

interface SystemViewProps {
  showToast: (message: string, type?: 'success' | 'error' | 'info') => void;
}

export const SystemView: React.FC<SystemViewProps> = ({ showToast }) => {
  const { user } = useAuth();
  const isAdmin = user?.rol === 'ADMIN';

  const [services, setServices] = useState<ServiceStatus[]>([]);
  const [loadingServices, setLoadingServices] = useState<boolean>(true);
  const [savingConfig, setSavingConfig] = useState<boolean>(false);
  const [syncingDhcp, setSyncingDhcp] = useState<boolean>(false);
  const [runningBackup, setRunningBackup] = useState<boolean>(false);
  const [rebuildingHosts, setRebuildingHosts] = useState<boolean>(false);

  // Estados de Configuración de Kea y Reinicios de Servicios (V1.7)
  const [keaConfig, setKeaConfig] = useState<string>('');
  const [showConfigModal, setShowConfigModal] = useState<boolean>(false);
  const [loadingConfig, setLoadingConfig] = useState<boolean>(false);
  const [restartingService, setRestartingService] = useState<string | null>(null);
  const [configSource, setConfigSource] = useState<'memoria' | 'disco'>('disco');

  // Estados para el Explorador de Backups SRE (V1.8)
  interface BackupFile {
    fileName: string;
    sizeBytes: number;
    lastModified: string;
    type: string;
  }

  const [backups, setBackups] = useState<BackupFile[]>([]);
  const [loadingBackups, setLoadingBackups] = useState<boolean>(false);
  const [downloadingFile, setDownloadingFile] = useState<string | null>(null);

  // Campos del Formulario (Configuraciones dinámicas de base de datos)
  const [telegramToken, setTelegramToken] = useState<string>('');
  const [telegramChatId, setTelegramChatId] = useState<string>('');
  const [leaseTimeHours, setLeaseTimeHours] = useState<number>(24);
  const [ispName, setIspName] = useState<string>('MMC');
  const [backupRetentionDays, setBackupRetentionDays] = useState<number>(7);
  const [backupRemoteHost, setBackupRemoteHost] = useState<string>('192.168.2.X');
  const [backupRemoteUser, setBackupRemoteUser] = useState<string>('usuario');
  const [backupRemotePath, setBackupRemotePath] = useState<string>('/home/usuario/backups_spi');

  const [showToken, setShowToken] = useState<boolean>(false);

  // Cargar estado de contenedores
  const fetchServicesStatus = async (silent = false) => {
    if (!silent) setLoadingServices(true);
    const res = await apiFetch<ServiceStatus[]>('/api/system/services-status');
    if (res.success && res.data) {
      setServices(res.data);
    } else {
      showToast('No se pudo actualizar el estado del NOC', 'error');
    }
    if (!silent) setLoadingServices(false);
  };

  // Cargar configuraciones (solo si es ADMIN o OPERADOR)
  const fetchConfig = async () => {
    const res = await apiFetch<Record<string, string>>('/api/system/config');
    if (res.success && res.data) {
      setTelegramToken(res.data['telegram_bot_token'] || '');
      setTelegramChatId(res.data['telegram_chat_id'] || '');
      
      const leaseSeconds = parseInt(res.data['dhcp_lease_time'] || '86400', 10);
      setLeaseTimeHours(Math.round(leaseSeconds / 3600));

      setIspName(res.data['isp_name'] || 'MMC');
      setBackupRetentionDays(parseInt(res.data['backup_retention_days'] || '7', 10));
      setBackupRemoteHost(res.data['backup_remote_host'] || '192.168.2.X');
      setBackupRemoteUser(res.data['backup_remote_user'] || 'usuario');
      setBackupRemotePath(res.data['backup_remote_path'] || '/home/usuario/backups_spi');
    } else {
      // Si el operador normal entra, no puede leer secretos pero cargamos valores mock de solo visualización
      if (!isAdmin) {
        setIspName('MMC');
        setBackupRetentionDays(7);
      }
    }
  };

  useEffect(() => {
    fetchServicesStatus();
    fetchConfig();
    if (isAdmin) {
      fetchBackups();
    }

    // Intervalo de auto-refresco del NOC cada 15 segundos para todos los roles
    const timer = setInterval(() => {
      fetchServicesStatus(true);
    }, 15000);

    return () => clearInterval(timer);
  }, []);

  // Listar backups SRE (V1.8)
  const fetchBackups = async (silent = false) => {
    if (!isAdmin) return;
    if (!silent) setLoadingBackups(true);
    const res = await apiFetch<BackupFile[]>('/api/system/backups');
    if (res.success && res.data) {
      setBackups(res.data);
    } else if (!silent) {
      showToast(res.error || 'No se pudo recuperar la lista de copias de seguridad', 'error');
    }
    if (!silent) setLoadingBackups(false);
  };

  // Descargar backup por streaming chunked seguro (V1.8)
  const handleDownloadBackup = async (fileName: string) => {
    if (!isAdmin || downloadingFile) return;

    setDownloadingFile(fileName);
    try {
      const token = getAccessToken();
      const headers: Record<string, string> = {};
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const response = await fetch(`/api/system/backups/download/${encodeURIComponent(fileName)}`, {
        headers,
        credentials: 'include'
      });

      if (!response.ok) {
        let errMsg = 'No se pudo descargar el archivo.';
        try {
          const errData = await response.json();
          errMsg = errData.error || errMsg;
        } catch {
          // No es JSON
        }
        showToast(errMsg, 'error');
        setDownloadingFile(null);
        return;
      }

      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = fileName;
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);
      showToast(`Archivo ${fileName} descargado con éxito`, 'success');
    } catch (err: any) {
      showToast(`Error al procesar la descarga: ${err.message}`, 'error');
    } finally {
      setDownloadingFile(null);
    }
  };

  // Guardar Parámetros de Red
  const handleSaveConfig = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isAdmin) return;

    if (leaseTimeHours <= 0) {
      showToast('El tiempo de lease debe ser un número entero de horas positivo', 'error');
      return;
    }
    if (backupRetentionDays <= 0) {
      showToast('La retención de backups debe ser al menos de 1 día', 'error');
      return;
    }

    setSavingConfig(true);
    const leaseSeconds = leaseTimeHours * 3600;
    
    const payload = {
      'telegram_bot_token': telegramToken,
      'telegram_chat_id': telegramChatId,
      'dhcp_lease_time': leaseSeconds.toString(),
      'isp_name': ispName,
      'backup_retention_days': backupRetentionDays.toString(),
      'backup_remote_host': backupRemoteHost,
      'backup_remote_user': backupRemoteUser,
      'backup_remote_path': backupRemotePath,
    };

    const res = await apiFetch('/api/system/config', {
      method: 'PUT',
      body: JSON.stringify(payload),
    });

    if (res.success) {
      showToast('Ajustes dinámicos guardados y aplicados con éxito', 'success');
      // Despachar evento para que Sidebar y Header carguen el nuevo ISP Name de inmediato
      window.dispatchEvent(new Event('isp-name-changed'));
      fetchConfig();
    } else {
      showToast(res.error || 'Fallo al guardar ajustes', 'error');
    }
    setSavingConfig(false);
  };

  // Forzar sincronización de Kea
  const handleDhcpSync = async () => {
    if (!isAdmin || syncingDhcp) return;

    setSyncingDhcp(true);
    const res = await apiFetch('/api/system/dhcp-sync', { method: 'POST' });
    if (res.success) {
      showToast('Recarga caliente de Kea completada con éxito', 'success');
      fetchServicesStatus();
    } else {
      showToast(res.error || 'Error al recargar Kea', 'error');
    }
    setSyncingDhcp(false);
  };
 
  // Reconstrucción completa de emergencia de la base de datos de Kea
  const handleRebuildKeaHosts = async () => {
    if (!isAdmin || rebuildingHosts) return;
 
    if (!window.confirm("¿Está seguro de que desea reconstruir la base de datos de Kea? Esta operación purgará y volverá a inyectar todas las reservas fijas de red para todos los clientes activos.")) return;
 
    setRebuildingHosts(true);
    const res = await apiFetch<{ message: string; suscripcionesReactivadas?: number }>('/api/system/rebuild-kea-hosts', { method: 'POST' });
    if (res.success && res.data) {
      const count = res.data.suscripcionesReactivadas ?? 0;
      showToast(`Reconstrucción de emergencia exitosa. Se sincronizaron ${count} abonados activos.`, 'success');
      fetchServicesStatus();
    } else {
      showToast(res.error || 'Error al reconstruir base de datos de Kea', 'error');
    }
    setRebuildingHosts(false);
  };

  // Trigger Backup Manual
  const handleBackupManual = async () => {
    if (!isAdmin || runningBackup) return;

    setRunningBackup(true);
    const res = await apiFetch('/api/system/backup-manual', { method: 'POST' });
    if (res.success) {
      showToast('Copia de seguridad manual iniciada en segundo plano', 'info');
    } else {
      showToast(res.error || 'Error al iniciar copia de seguridad', 'error');
    }
    setRunningBackup(false);
  };

  // Obtener e inspeccionar config de Kea (V1.7)
  const handleViewKeaConfig = async () => {
    setLoadingConfig(true);
    const res = await apiFetch<{ config: string; source: 'memoria' | 'disco' }>('/api/system/kea-config');
    setLoadingConfig(false);
    if (res.success && res.data) {
      setKeaConfig(res.data.config);
      setConfigSource(res.data.source);
      setShowConfigModal(true);
    } else {
      showToast(res.error || 'No se pudo obtener la configuración de Kea', 'error');
    }
  };

  // Reiniciar un contenedor del sistema (V1.7)
  const handleRestartService = async (serviceName: string) => {
    if (!window.confirm(`¿Está seguro de que desea reiniciar el servicio ${getContainerAlias(serviceName)} (${serviceName})?`)) return;
    setRestartingService(serviceName);
    const res = await apiFetch('/api/system/restart-service', {
      method: 'POST',
      body: JSON.stringify({ serviceName })
    });
    setRestartingService(null);
    if (res.success) {
      showToast(`El servicio ${getContainerAlias(serviceName)} ha sido reiniciado con éxito.`, 'success');
      fetchServicesStatus(true);
    } else {
      showToast(res.error || 'Error al reiniciar el servicio', 'error');
    }
  };

  const getStatusColor = (state: string) => {
    switch (state) {
      case 'healthy': return { badgeClass: 'badge-active' };
      case 'starting': return { badgeClass: 'badge-suspended' };
      case 'unhealthy': return { badgeClass: 'badge-danger' };
      default: return { badgeClass: 'badge-neutral' };
    }
  };

  const getContainerAlias = (name: string) => {
    switch (name) {
      case 'isp-postgres': return 'Base de Datos (PostgreSQL)';
      case 'isp-kea-dhcp': return 'Servidor DHCP (Kea Core)';
      case 'isp-admin-api': return 'Motor API (.NET Backend)';
      case 'isp-web-client': return 'Consola Web (Nginx Frontend)';
      case 'isp-backup-manager': return 'Gestor de Resguardos y SRE';
      default: return name;
    }
  };

  return (
    <div className="view-container">
      {/* 1. Header de Vista */}
      <header>
        <div>
          <h1>Consola de Sistema</h1>
          <p className="subtitle">Monitoreo del NOC, orquestación SRE de contenedores y ajustes del servidor</p>
        </div>
        <button 
          onClick={() => fetchServicesStatus()} 
          disabled={loadingServices}
          className="btn btn-secondary"
        >
          <RefreshCw size={14} className={loadingServices ? 'animate-spin' : ''} style={{ marginRight: '6px' }} />
          Refrescar NOC
        </button>
      </header>

      {/* 2. Sección del NOC - Live Health Cards */}
      <div style={{ marginBottom: '24px' }}>
        <h2 style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-main)', marginBottom: '12px', display: 'flex', alignItems: 'center', gap: '8px' }}>
          <Activity size={16} style={{ color: 'var(--accent-cyan)' }} />
          Monitoreo en Tiempo Real de Infraestructura (NOC)
        </h2>
        
        <div className="metrics-grid">
          {loadingServices ? (
            Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="metric-card" style={{ animation: 'pulse 1.5s infinite' }}>
                <div style={{ height: '12px', backgroundColor: 'var(--border-color)', width: '60%', marginBottom: '10px' }}></div>
                <div style={{ height: '18px', backgroundColor: 'var(--border-color)', width: '40%', marginBottom: '12px' }}></div>
                <div style={{ height: '10px', backgroundColor: 'var(--border-color)', width: '90%' }}></div>
              </div>
            ))
          ) : (
            services.map((srv) => {
              const styles = getStatusColor(srv.state);
              return (
                <div 
                  key={srv.name} 
                  className="metric-card"
                  style={{ position: 'relative' }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                    <span style={{ fontSize: '10px', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>CONTENEDOR</span>
                    <span className={`badge ${styles.badgeClass}`}>
                      {srv.state}
                    </span>
                  </div>
                  <h4 style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-main)', margin: '4px 0' }}>
                    {getContainerAlias(srv.name)}
                  </h4>
                  <p style={{ fontSize: '11px', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)', marginTop: '8px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={srv.rawStatus}>
                    {srv.rawStatus}
                  </p>
                  {isAdmin && srv.isUp && (
                    <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '12px', borderTop: '1px dashed var(--border-color)', paddingTop: '8px' }}>
                      <button
                        onClick={() => handleRestartService(srv.name)}
                        disabled={restartingService === srv.name}
                        className="btn-icon"
                        style={{
                          fontSize: '10px',
                          color: 'var(--text-muted)',
                          display: 'flex',
                          alignItems: 'center',
                          gap: '6px',
                          cursor: 'pointer',
                          backgroundColor: 'transparent',
                          border: 'none',
                          padding: '4px 0',
                          width: '100%',
                          justifyContent: 'center',
                          transition: 'opacity 0.2s'
                        }}
                        title={`Reiniciar contenedor ${srv.name}`}
                      >
                        <RotateCw size={10} className={restartingService === srv.name ? 'animate-spin' : ''} style={{ color: 'var(--accent-red)' }} />
                        <span style={{ color: 'var(--text-muted)', fontWeight: 500 }}>
                          {restartingService === srv.name ? 'Reiniciando...' : 'Reiniciar Servicio'}
                        </span>
                      </button>
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>
      </div>

      {/* 3. Panel de Ajustes y Triggers de Emergencia */}
      <div className="grid-2col">
        {/* Panel Izquierdo: Ajustes de Configuración */}
        <div className="panel">
          <div className="panel-header">
            <div className="panel-title">
              <Settings size={14} style={{ color: 'var(--accent-cyan)' }} />
              <h3>Parámetros del Sistema y DHCP</h3>
            </div>
          </div>

          {!isAdmin && (
            <div style={{ display: 'flex', gap: '8px', padding: '10px', backgroundColor: 'var(--bg-tertiary)', border: '1px solid var(--border-color)', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '16px' }}>
              <ShieldAlert size={16} style={{ color: 'var(--warning)', flexShrink: 0 }} />
              <div>
                <strong style={{ color: 'var(--text-main)' }}>Modo de Solo Visualización</strong>
                <p style={{ marginTop: '2px' }}>Tienes acceso completo a la telemetría en vivo del NOC. La modificación de credenciales y el lanzamiento de triggers de resguardo o sincronización de red está restringida para Súper Administradores.</p>
              </div>
            </div>
          )}

          <form onSubmit={handleSaveConfig} className="form-container">
            {/* Sección 1: White-Label */}
            <div className="panel" style={{ padding: '12px', marginBottom: '12px' }}>
              <div className="panel-header" style={{ marginBottom: '8px', paddingBottom: '6px' }}>
                <div className="panel-title" style={{ fontSize: '11px' }}>
                  <Globe size={12} style={{ color: 'var(--accent-cyan)' }} />
                  <span>Personalización Comercial de Marca (White-Label)</span>
                </div>
              </div>
              <div className="form-grid">
                <div className="form-group">
                  <label>Nombre del ISP (Fantasía)</label>
                  <input
                    type="text"
                    value={ispName}
                    onChange={(e) => setIspName(e.target.value)}
                    disabled={!isAdmin}
                    placeholder="Ej: MMC"
                  />
                </div>
                <div className="form-group">
                  <label>Tiempo de Concesión DHCP (Lease Time)</label>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <input
                      type="number"
                      value={leaseTimeHours}
                      onChange={(e) => setLeaseTimeHours(Math.max(1, parseInt(e.target.value, 10) || 0))}
                      disabled={!isAdmin}
                      min={1}
                      style={{ width: '80px', textAlign: 'center' }}
                    />
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>horas exactas</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Sección 2: Telegram */}
            <div className="panel" style={{ padding: '12px', marginBottom: '12px' }}>
              <div className="panel-header" style={{ marginBottom: '8px', paddingBottom: '6px' }}>
                <div className="panel-title" style={{ fontSize: '11px' }}>
                  <ShieldAlert size={12} style={{ color: 'var(--accent-cyan)' }} />
                  <span>Alertas y Notificaciones NOC (Telegram)</span>
                </div>
              </div>
              <div className="form-grid">
                <div className="form-group">
                  <label>Telegram Bot Token</label>
                  <div className="input-with-icon" style={{ display: 'flex', alignItems: 'center', position: 'relative' }}>
                    <input
                      type={showToken ? 'text' : 'password'}
                      value={telegramToken}
                      onChange={(e) => setTelegramToken(e.target.value)}
                      disabled={!isAdmin}
                      placeholder={isAdmin ? "Token de BotFather" : "••••••••••••••••••••"}
                      style={{ width: '100%' }}
                    />
                    {isAdmin && (
                      <button
                        type="button"
                        onClick={() => setShowToken(!showToken)}
                        style={{ position: 'absolute', right: '10px', background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', display: 'flex', alignItems: 'center' }}
                      >
                        {showToken ? <EyeOff size={14} /> : <Eye size={14} />}
                      </button>
                    )}
                  </div>
                </div>
                <div className="form-group">
                  <label>Telegram Chat ID</label>
                  <input
                    type="text"
                    value={telegramChatId}
                    onChange={(e) => setTelegramChatId(e.target.value)}
                    disabled={!isAdmin}
                    placeholder={isAdmin ? "Ej: -100123456789" : "Oculto"}
                  />
                </div>
              </div>
            </div>

            {/* Sección 3: Política de Resguardos */}
            <div className="panel" style={{ padding: '12px', marginBottom: '12px' }}>
              <div className="panel-header" style={{ marginBottom: '8px', paddingBottom: '6px' }}>
                <div className="panel-title" style={{ fontSize: '11px' }}>
                  <Database size={12} style={{ color: 'var(--accent-cyan)' }} />
                  <span>Estrategia de Resguardos y Réplicas SRE</span>
                </div>
              </div>
              <div className="form-grid">
                <div className="form-group">
                  <label>Días de Retención</label>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <input
                      type="number"
                      value={backupRetentionDays}
                      onChange={(e) => setBackupRetentionDays(Math.max(1, parseInt(e.target.value, 10) || 0))}
                      disabled={!isAdmin}
                      min={1}
                      style={{ width: '80px', textAlign: 'center' }}
                    />
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>días de antigüedad</span>
                  </div>
                </div>
                <div className="form-group">
                  <label>Host Remoto SCP (Réplica)</label>
                  <input
                    type="text"
                    value={backupRemoteHost}
                    onChange={(e) => setBackupRemoteHost(e.target.value)}
                    disabled={!isAdmin}
                    placeholder="Ej: 192.168.2.107 (o '192.168.2.X')"
                  />
                </div>
              </div>
              <div className="form-grid" style={{ marginTop: '8px' }}>
                <div className="form-group">
                  <label>Usuario SSH Réplica</label>
                  <input
                    type="text"
                    value={backupRemoteUser}
                    onChange={(e) => setBackupRemoteUser(e.target.value)}
                    disabled={!isAdmin}
                    placeholder="Ej: usuario"
                  />
                </div>
                <div className="form-group">
                  <label>Directorio SCP Remoto</label>
                  <input
                    type="text"
                    value={backupRemotePath}
                    onChange={(e) => setBackupRemotePath(e.target.value)}
                    disabled={!isAdmin}
                    placeholder="Ej: /home/usuario/backups_spi"
                  />
                </div>
              </div>
            </div>

            {isAdmin && (
              <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '16px' }}>
                <button
                  type="submit"
                  disabled={savingConfig}
                  className="btn btn-primary"
                  style={{ padding: '8px 16px' }}
                >
                  {savingConfig ? 'Guardando...' : 'Aplicar Parámetros en Caliente'}
                </button>
              </div>
            )}
          </form>
        </div>

        {/* Panel Derecho: Triggers de Emergencia */}
        <div className="panel">
          <div className="panel-header">
            <div className="panel-title">
              <Server size={14} style={{ color: 'var(--accent-cyan)' }} />
              <h3>Acciones SRE Críticas</h3>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            {/* Sincronización Manual */}
            <div className="panel" style={{ padding: '12px', marginBottom: '0' }}>
              <h4 style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-main)', marginBottom: '6px' }}>Forzar Recarga DHCP</h4>
              <p style={{ fontSize: '11px', color: 'var(--text-muted)', lineHeight: '1.4', marginBottom: '12px' }}>
                Regenera atómicamente el archivo de configuración global `kea-dhcp4.conf` desde las subredes y pools en la BD y gatilla el comando de recarga REST in-memory en Kea.
              </p>
              <button
                onClick={handleDhcpSync}
                disabled={!isAdmin || syncingDhcp}
                className="btn btn-secondary"
                style={{ width: '100%', padding: '8px' }}
              >
                <RefreshCw size={12} className={syncingDhcp ? 'animate-spin' : ''} style={{ marginRight: '6px' }} />
                {syncingDhcp ? 'Recargando...' : 'Ejecutar Sincronización'}
              </button>
            </div>

            {/* Reconstrucción de Emergencia SRE */}
            {isAdmin && (
              <div className="panel" style={{ padding: '12px', marginBottom: '0', border: '1px solid rgba(239, 68, 68, 0.2)', backgroundColor: 'rgba(239, 68, 68, 0.02)' }}>
                <h4 style={{ fontSize: '12px', fontWeight: 600, color: 'var(--accent-red)', marginBottom: '6px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <ShieldAlert size={14} style={{ color: 'var(--accent-red)' }} />
                  Reconstrucción de Emergencia
                </h4>
                <p style={{ fontSize: '11px', color: 'var(--text-muted)', lineHeight: '1.4', marginBottom: '12px' }}>
                  Re-popula la base de datos de reservas de Kea (`public.hosts`) ejecutando el trigger para cada abonado activo, regenera `kea-dhcp4.conf` y recarga Kea DHCP en memoria.
                </p>
                <button
                  onClick={handleRebuildKeaHosts}
                  disabled={rebuildingHosts}
                  className="btn"
                  style={{ 
                    width: '100%', 
                    padding: '8px', 
                    backgroundColor: 'var(--accent-red)', 
                    color: 'white',
                    border: 'none',
                    borderRadius: '4px',
                    fontWeight: 600,
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '6px',
                    transition: 'opacity 0.2s',
                    opacity: rebuildingHosts ? 0.7 : 1
                  }}
                >
                  <RotateCw size={12} className={rebuildingHosts ? 'animate-spin' : ''} />
                  {rebuildingHosts ? 'Reconstruyendo Red...' : 'Iniciar Reconstrucción Completa'}
                </button>
              </div>
            )}

            {/* Iniciar Backup Manual */}
            <div className="panel" style={{ padding: '12px', marginBottom: '0' }}>
              <h4 style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-main)', marginBottom: '6px' }}>Backup Manual SRE</h4>
              <p style={{ fontSize: '11px', color: 'var(--text-muted)', lineHeight: '1.4', marginBottom: '12px' }}>
                Lanza asíncronamente en el contenedor de backups la tarea de copia de seguridad (dump SQL completo, tarball de configs y archivos TFTP) con aserción e integridad activa.
              </p>
              <button
                onClick={handleBackupManual}
                disabled={!isAdmin || runningBackup}
                className="btn btn-success"
                style={{ width: '100%', padding: '8px' }}
              >
                <Play size={12} style={{ marginRight: '6px' }} />
                {runningBackup ? 'Lanzando Tarea...' : 'Iniciar Resguardo'}
              </button>
            </div>

            {/* Inspeccionar Configuración Kea (V1.7) */}
            {isAdmin && (
              <div className="panel" style={{ padding: '12px', marginBottom: '0' }}>
                <h4 style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-main)', marginBottom: '6px' }}>Configuración de Kea DHCP</h4>
                <p style={{ fontSize: '11px', color: 'var(--text-muted)', lineHeight: '1.4', marginBottom: '12px' }}>
                  Inspecciona en tiempo real el archivo de configuración `kea-dhcp4.conf` activo y corriendo en caliente en el servidor de producción.
                </p>
                <button
                  onClick={handleViewKeaConfig}
                  disabled={loadingConfig}
                  className="btn btn-secondary"
                  style={{ width: '100%', padding: '8px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}
                >
                  <FileJson size={12} className={loadingConfig ? 'animate-spin' : ''} />
                  {loadingConfig ? 'Obteniendo...' : 'Ver Configuración en Vivo'}
                </button>
              </div>
            )}

            {/* Advertencia de Seguridad */}
            <div style={{ display: 'flex', gap: '8px', padding: '10px', backgroundColor: 'rgba(234, 179, 8, 0.05)', border: '1px solid rgba(234, 179, 8, 0.2)', fontSize: '11px', color: 'var(--warning)' }}>
              <AlertTriangle size={16} style={{ flexShrink: 0 }} />
              <p style={{ lineHeight: '1.4' }}>Estas operaciones se aplican directo sobre el host de producción. Úsalas con responsabilidad en horarios de mantenimiento o contingencias técnicas.</p>
            </div>
          </div>
        </div>
      </div>

      {/* 4. Sección de Explorador de Backups SRE (V1.8) */}
      {isAdmin && (
        <div className="panel" style={{ marginTop: '24px' }}>
          <div className="panel-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div className="panel-title">
              <Database size={14} style={{ color: 'var(--accent-cyan)' }} />
              <h3>Historial de Copias de Seguridad SRE (Solo Lectura)</h3>
            </div>
            <button
              onClick={() => fetchBackups()}
              disabled={loadingBackups}
              className="btn btn-secondary btn-small"
              style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '11px', padding: '6px 12px' }}
            >
              <RefreshCw size={11} className={loadingBackups ? 'animate-spin' : ''} />
              Actualizar Lista
            </button>
          </div>

          <div style={{ padding: '0px', overflow: 'hidden' }}>
            {loadingBackups ? (
              <div style={{ padding: '40px', textAlign: 'center', color: 'var(--text-muted)' }}>
                <div className="animate-spin" style={{ width: '24px', height: '24px', border: '2px solid var(--border-color)', borderTopColor: 'var(--border-active)', borderRadius: '50%', margin: '0 auto 12px auto' }}></div>
                <span>Buscando archivos de respaldo autorizados...</span>
              </div>
            ) : backups.length === 0 ? (
              <div style={{ padding: '30px', textAlign: 'center', color: 'var(--text-muted)', fontSize: '12px' }}>
                <FolderArchive size={28} style={{ opacity: 0.4, marginBottom: '8px', display: 'block', margin: '0 auto 8px auto' }} />
                <p>No se encontraron archivos de copia de seguridad (.sql, .tar, .tgz) en el almacén.</p>
                <p style={{ fontSize: '11px', opacity: 0.7, marginTop: '4px' }}>Presione "Iniciar Resguardo" en las acciones críticas para generar uno.</p>
              </div>
            ) : (
              <div className="table-responsive">
                <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '12px' }}>
                  <thead>
                    <tr style={{ backgroundColor: 'var(--bg-tertiary)', borderBottom: '1px solid var(--border-color)' }}>
                      <th style={{ padding: '12px 16px', fontWeight: 600 }}>Archivo de Resguardo</th>
                      <th style={{ padding: '12px 16px', fontWeight: 600 }}>Extensión</th>
                      <th style={{ padding: '12px 16px', fontWeight: 600 }}>Tamaño</th>
                      <th style={{ padding: '12px 16px', fontWeight: 600 }}>Última Modificación</th>
                      <th style={{ padding: '12px 16px', fontWeight: 600, textAlign: 'right' }}>Acción</th>
                    </tr>
                  </thead>
                  <tbody>
                    {backups.map((bk) => (
                      <tr key={bk.fileName} className="table-row" style={{ borderBottom: '1px solid var(--border-color)' }}>
                        <td style={{ padding: '12px 16px' }}>
                          <span style={{ fontWeight: 600, color: 'var(--text-main)' }}>{bk.fileName}</span>
                        </td>
                        <td style={{ padding: '12px 16px' }}>
                          <span style={{
                            fontSize: '10px',
                            backgroundColor: bk.type === 'sql' ? 'rgba(56, 189, 248, 0.1)' : 'rgba(168, 85, 247, 0.1)',
                            color: bk.type === 'sql' ? '#38bdf8' : '#a855f7',
                            padding: '2px 6px',
                            borderRadius: '4px',
                            fontWeight: 700,
                            textTransform: 'uppercase'
                          }}>
                            {bk.type}
                          </span>
                        </td>
                        <td style={{ padding: '12px 16px', color: 'var(--text-muted)' }}>
                          {(bk.sizeBytes / (1024 * 1024)).toFixed(2)} MB
                        </td>
                        <td style={{ padding: '12px 16px', color: 'var(--text-muted)' }}>
                          {new Date(bk.lastModified).toLocaleString()}
                        </td>
                        <td style={{ padding: '12px 16px', textAlign: 'right' }}>
                          <button
                            onClick={() => handleDownloadBackup(bk.fileName)}
                            disabled={downloadingFile !== null}
                            className="btn btn-secondary btn-small"
                            style={{ display: 'inline-flex', alignItems: 'center', gap: '6px', fontSize: '11px', padding: '6px 12px' }}
                            title="Descargar copia de seguridad por streaming"
                          >
                            <Download size={12} className={downloadingFile === bk.fileName ? 'animate-pulse' : ''} />
                            {downloadingFile === bk.fileName ? 'Transmitiendo...' : 'Descargar'}
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Modal de Configuración de Kea (V1.7) */}
      {showConfigModal && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          width: '100vw',
          height: '100vh',
          backgroundColor: 'rgba(0,0,0,0.85)',
          backdropFilter: 'blur(8px)',
          zIndex: 9999,
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          padding: '24px'
        }}>
          <div className="panel" style={{
            width: '100%',
            maxWidth: '900px',
            maxHeight: '85vh',
            display: 'flex',
            flexDirection: 'column',
            backgroundColor: 'var(--bg-secondary)',
            border: '1px solid var(--border-color)',
            borderRadius: '8px',
            boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.5)',
            overflow: 'hidden'
          }}>
            <div className="panel-header" style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              padding: '16px 20px',
              borderBottom: '1px solid var(--border-color)'
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <FileJson size={18} style={{ color: 'var(--accent-cyan)' }} />
                  <h3 style={{ margin: 0, fontSize: '15px', fontWeight: 700, color: 'var(--text-main)' }}>Configuración Activa de Kea</h3>
                </div>
                <span style={{
                  fontSize: '9px',
                  backgroundColor: configSource === 'memoria' ? 'rgba(16, 185, 129, 0.15)' : 'rgba(245, 158, 11, 0.15)',
                  color: configSource === 'memoria' ? '#10b981' : '#f59e0b',
                  border: `1px solid ${configSource === 'memoria' ? 'rgba(16, 185, 129, 0.3)' : 'rgba(245, 158, 11, 0.3)'}`,
                  padding: '2px 8px',
                  borderRadius: '4px',
                  fontWeight: 600,
                  textTransform: 'uppercase',
                  letterSpacing: '0.05em'
                }}>
                  {configSource === 'memoria' ? 'En Memoria (Live)' : 'De Disco (Fallback)'}
                </span>
              </div>
              <button
                onClick={() => setShowConfigModal(false)}
                className="btn btn-secondary"
                style={{ padding: '6px 12px', fontSize: '12px' }}
              >
                Cerrar
              </button>
            </div>
            
            <div style={{
              flex: 1,
              overflow: 'auto',
              padding: '20px',
              backgroundColor: '#07080d',
              borderRadius: '0 0 8px 8px'
            }}>
              <pre style={{
                margin: 0,
                fontFamily: 'var(--font-mono)',
                fontSize: '11px',
                lineHeight: '1.6',
                color: '#e2e8f0',
                whiteSpace: 'pre-wrap',
                wordBreak: 'break-all'
              }}>
                {keaConfig}
              </pre>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default SystemView;
