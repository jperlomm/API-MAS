import React, { useState, useEffect } from 'react';
import { Activity, Sliders, LayoutGrid, Users, Cpu, Network, Zap, Terminal, ShieldAlert, LogOut, Database, Settings } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { apiFetch } from '../utils/api';

interface SidebarProps {
  activeTab: string;
  setActiveTab: (tab: string) => void;
  activeMode: 'diagnostics' | 'management';
  setActiveMode: (mode: 'diagnostics' | 'management') => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ activeTab, setActiveTab, activeMode, setActiveMode }) => {
  const { user, logout } = useAuth();
  const [ispName, setIspName] = useState<string>('MMC');

  const fetchIspInfo = async () => {
    try {
      const res = await apiFetch<{ ispName: string }>('/api/system/isp-info');
      if (res.success && res.data?.ispName) {
        setIspName(res.data.ispName);
      }
    } catch {
      // ignore
    }
  };

  useEffect(() => {
    fetchIspInfo();
    window.addEventListener('isp-name-changed', fetchIspInfo);
    return () => {
      window.removeEventListener('isp-name-changed', fetchIspInfo);
    };
  }, []);

  const currentItems = activeMode === 'diagnostics'
    ? [
        { id: 'dashboard', label: '0. Dashboard NOC', icon: LayoutGrid },
        { id: 'system', label: '1. Consola Sistema', icon: Settings },
        ...(user?.rol === 'ADMIN' ? [
          { id: 'diagnostics', label: '2. Diagnóstico Kea', icon: Database },
          { id: 'usuarios', label: '3. Seguridad/Personal', icon: ShieldAlert }
        ] : [])
      ]
    : [
        { id: 'clientes', label: '0. Padrón Clientes', icon: Users },
        { id: 'servicios', label: '1. Aprovisionar', icon: Zap },
        { id: 'equipos', label: '2. Inventario Stock', icon: Cpu },
        { id: 'red', label: '3. Layout de Red', icon: Network },
        { id: 'bootfiles', label: '4. Gestor TFTP', icon: Terminal },
      ];

  return (
    <aside style={{ display: 'flex', flexDirection: 'column', height: '100vh' }}>
      <div className="logo-container">
        <div className="logo-icon">{ispName.charAt(0).toUpperCase()}</div>
        <div className="logo-text">{ispName} V1</div>
      </div>

      {/* Selector de Módulos (Segmented Toggle) */}
      <div className="mode-selector-wrapper">
        <span className="mode-selector-title">Entorno Seguro</span>
        <div className="mode-selector-switch">
          <button
            onClick={() => setActiveMode('diagnostics')}
            className={`mode-selector-btn ${activeMode === 'diagnostics' ? 'active' : ''}`}
            title="Diagnósticos & Telemetría"
          >
            <Activity size={12} />
            Diagnóstico
          </button>
          <button
            onClick={() => setActiveMode('management')}
            className={`mode-selector-btn ${activeMode === 'management' ? 'active' : ''}`}
            title="Registro & Altas"
          >
            <Sliders size={12} />
            Gestión
          </button>
        </div>
      </div>

      {/* Título de la Sección de Navegación */}
      <div className="sidebar-section-header">
        {activeMode === 'diagnostics' ? 'Monitoreo & NOC' : 'Registros & Altas'}
      </div>
      
      <nav style={{ flexGrow: 1, display: 'flex', flexDirection: 'column', gap: '4px' }}>
        {currentItems.map((item) => {
          const IconComponent = item.icon;
          return (
            <button
              key={item.id}
              onClick={() => setActiveTab(item.id)}
              className={`nav-link ${activeTab === item.id ? 'active' : ''}`}
            >
              <IconComponent size={18} strokeWidth={2} />
              {item.label}
            </button>
          );
        })}

        {/* Botón de Salida con Estilo de Destacado de Salida */}
        <button
          onClick={logout}
          className="nav-link logout-btn"
          style={{
            marginTop: 'auto',
            color: '#f87171',
            borderRadius: '8px',
            transition: 'all 0.2s ease',
          }}
        >
          <LogOut size={18} strokeWidth={2} />
          Cerrar Sesión
        </button>
      </nav>

      <div className="footer-brand" style={{ marginTop: '20px' }}>
        <p style={{ fontWeight: 600 }}>{ispName} Core v1.1.0</p>
        <p style={{ marginTop: '4px', opacity: 0.5 }}>React + TS / PostgreSQL</p>
      </div>
    </aside>
  );
};

export default Sidebar;
