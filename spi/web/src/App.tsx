import { useState, useEffect } from 'react';
import Sidebar from './components/Sidebar';
import Header from './components/Header';
import Toast from './components/Toast';

// Contexto de Seguridad
import { AuthProvider, useAuth } from './context/AuthContext';

// Vistas modulares
import DashboardView from './views/DashboardView';
import ClientesView from './views/ClientesView';
import EquiposView from './views/EquiposView';
import RedView from './views/RedView';
import SuscripcionesView from './views/SuscripcionesView';
import BootfilesView from './views/BootfilesView';
import LoginView from './views/LoginView';
import UsuariosView from './views/UsuariosView';
import { DiagnosticsView } from './views/DiagnosticsView';
import { SystemView } from './views/SystemView';

interface ToastState {
  message: string;
  type: 'success' | 'error' | 'info';
}

function AppContent() {
  const { isAuthenticated, loading, user } = useAuth();
  const [activeTab, setActiveTab] = useState<string>('clientes');
  const [activeMode, setActiveMode] = useState<'diagnostics' | 'management'>('management');
  const [toast, setToast] = useState<ToastState | null>(null);

  // Sincronizar clases globales de modo en el body para activar acentos y glows de diseño
  useEffect(() => {
    if (!isAuthenticated) return;
    document.body.classList.remove('mode-diagnostics', 'mode-management');
    document.body.classList.add(activeMode === 'diagnostics' ? 'mode-diagnostics' : 'mode-management');
  }, [activeMode, isAuthenticated]);

  const handleModeChange = (mode: 'diagnostics' | 'management') => {
    setActiveMode(mode);
    if (mode === 'diagnostics') {
      setActiveTab('dashboard');
    } else {
      setActiveTab('clientes');
    }
  };

  const showToast = (message: string, type: 'success' | 'error' | 'info' = 'success') => {
    setToast({ message, type });
  };

  const clearToast = () => {
    setToast(null);
  };

  const renderView = () => {
    switch (activeTab) {
      case 'dashboard':
        return <DashboardView showToast={showToast} />;
      case 'clientes':
        return <ClientesView showToast={showToast} />;
      case 'equipos':
        return <EquiposView showToast={showToast} />;
      case 'red':
        return <RedView showToast={showToast} />;
      case 'servicios':
        return <SuscripcionesView showToast={showToast} />;
      case 'bootfiles':
        return <BootfilesView showToast={showToast} />;
      case 'usuarios':
        if (user?.rol === 'ADMIN') {
          return <UsuariosView showToast={showToast} />;
        }
        return <DashboardView showToast={showToast} />;
      case 'diagnostics':
        if (user?.rol === 'ADMIN') {
          return <DiagnosticsView showToast={showToast} />;
        }
        return <DashboardView showToast={showToast} />;
      case 'system':
        return <SystemView showToast={showToast} />;
      default:
        return <DashboardView showToast={showToast} />;
    }
  };


  // 1. Splash Screen de inicialización silenciosa
  if (loading) {
    return (
      <div style={styles.splashContainer}>
        <div style={styles.spinner}></div>
        <p style={styles.splashText}>Cargando entorno seguro de aprovisionamiento...</p>
      </div>
    );
  }

  // 2. Forzar Login si el operador no está autenticado
  if (!isAuthenticated) {
    return (
      <LoginView 
        onLoginSuccess={() => showToast(`¡Bienvenido de nuevo al SPI!`, 'success')} 
      />
    );
  }

  // 3. Renderizar Layout normal del SPI si el operador está verificado
  return (
    <>
      <Sidebar 
        activeTab={activeTab} 
        setActiveTab={setActiveTab} 
        activeMode={activeMode} 
        setActiveMode={handleModeChange} 
      />
      
      <main>
        <Header activeTab={activeTab} activeMode={activeMode} />
        <div key={activeTab} className="animate-slide-up">
          {renderView()}
        </div>
      </main>

      {toast && (
        <Toast 
          message={toast.message} 
          type={toast.type} 
          onClose={clearToast} 
        />
      )}
    </>
  );
}

// Estilos locales de soporte rápido
const styles = {
  splashContainer: {
    display: 'flex',
    flexDirection: 'column' as const,
    justifyContent: 'center',
    alignItems: 'center',
    minHeight: '100vh',
    width: '100vw',
    backgroundColor: '#0a0b10',
    fontFamily: "'Outfit', 'Inter', sans-serif",
  },
  spinner: {
    width: '40px',
    height: '40px',
    borderRadius: '50%',
    border: '3px solid rgba(255, 255, 255, 0.1)',
    borderTopColor: '#6366f1',
    animation: 'spin 0.8s linear infinite',
  },
  splashText: {
    marginTop: '16px',
    color: '#94a3b8',
    fontSize: '14px',
    letterSpacing: '0.5px',
  },
};

// Inyección de animaciones globales para Splash
if (typeof document !== 'undefined') {
  const styleSheet = document.createElement('style');
  styleSheet.type = 'text/css';
  styleSheet.innerText = `
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
  `;
  document.head.appendChild(styleSheet);
}

function App() {
  return (
    <AuthProvider>
      <AppContent />
    </AuthProvider>
  );
}

export default App;
