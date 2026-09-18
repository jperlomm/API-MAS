import React, { useState, useEffect } from 'react';
import { Sun, Moon } from 'lucide-react';

interface HeaderProps {
  activeTab: string;
  activeMode: 'diagnostics' | 'management';
}

export const Header: React.FC<HeaderProps> = ({ activeTab, activeMode }) => {
  const [theme, setTheme] = useState<'dark' | 'light'>(() => {
    return (localStorage.getItem('theme') as 'dark' | 'light') || 'dark';
  });

  useEffect(() => {
    if (theme === 'light') {
      document.documentElement.classList.add('light-mode');
      document.body.classList.add('light-mode');
    } else {
      document.documentElement.classList.remove('light-mode');
      document.body.classList.remove('light-mode');
    }
    localStorage.setItem('theme', theme);
  }, [theme]);

  const toggleTheme = () => {
    setTheme(prev => prev === 'dark' ? 'light' : 'dark');
  };

  const getHeaderInfo = () => {
    switch (activeTab) {
      case 'dashboard':
        return {
          title: 'Dashboard NOC',
          subtitle: 'Métricas críticas, alertas de aprovisionamiento en caliente y telemetría de red en tiempo real.',
        };
      case 'red':
        return {
          title: 'Layout de Red',
          subtitle: 'Topología física, CMTSs, subredes, pools de IP DHCP y perfiles.',
        };
      case 'bootfiles':
        return {
          title: 'Gestor TFTP',
          subtitle: 'Administración de bootfiles binarios .bin y scripts .bat para aprovisionamiento DOCSIS.',
        };
      case 'equipos':
        return {
          title: 'Inventario de Stock',
          subtitle: 'Stock físico de cablemódems y ONUs, marcas, modelos y asignación de hardware.',
        };
      case 'clientes':
        return {
          title: 'Padrón de Clientes',
          subtitle: 'Administración de abonados, datos de contacto y facturación de servicios.',
        };
      case 'servicios':
        return {
          title: 'Aprovisionar Servicio',
          subtitle: 'Aprovisionamiento de servicios de internet e inyección DHCP en tiempo real.',
        };
      case 'diagnostics':
        return {
          title: 'Diagnóstico Kea DHCP',
          subtitle: 'Visor de leases activos, reservas de red estáticas y auditoría de red.',
        };
      case 'system':
        return {
          title: 'Consola del Sistema',
          subtitle: 'Estado de servicios, daemon DHCP, respaldos y parámetros globales.',
        };
      case 'usuarios':
        return {
          title: 'Seguridad y Personal',
          subtitle: 'Gestión de accesos de operadores, roles y auditoría de seguridad.',
        };
      default:
        return {
          title: 'Consola Central',
          subtitle: 'Entorno integrado de gestión de redes y abonados.',
        };
    }
  };

  const info = getHeaderInfo();

  return (
    <header style={{ paddingBottom: '16px', marginBottom: '24px' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
        {/* Breadcrumb Técnico con Badge de Módulo */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
          <span className={`module-badge ${activeMode === 'diagnostics' ? 'module-badge-diagnostics' : 'module-badge-management'}`}>
            {activeMode === 'diagnostics' ? 'Soporte & Diagnóstico' : 'Administración & Altas'}
          </span>
          <span style={{ color: 'var(--text-muted)', fontSize: '11px', opacity: 0.7 }}>/</span>
          <span style={{ color: 'var(--text-muted)', fontSize: '11px', fontFamily: 'var(--font-mono)' }}>{info.title.toLowerCase().replace(/\s+/g, '-')}</span>
        </div>
        <h1 style={{ margin: '4px 0 0 0', fontSize: '18px', fontWeight: 700, letterSpacing: '-0.3px' }}>{info.title}</h1>
        <div className="subtitle" style={{ marginTop: '2px' }}>{info.subtitle}</div>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
        {/* Toggle Minimalista de Modo Claro / Modo Oscuro */}
        <button
          onClick={toggleTheme}
          className="btn-icon"
          style={{
            padding: '4px',
            height: '24px',
            width: '24px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            cursor: 'pointer',
          }}
          title={theme === 'dark' ? 'Modo Claro' : 'Modo Oscuro'}
        >
          {theme === 'dark' ? <Sun size={12} /> : <Moon size={12} />}
        </button>
        <div className="sys-status">
          <div className="pulse-dot" />
          <span style={{ letterSpacing: '0.5px' }}>KEA DHCP & API .NET 8 ONLINE</span>
        </div>
      </div>
    </header>
  );
};

export default Header;
