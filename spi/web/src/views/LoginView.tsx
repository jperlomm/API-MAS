import React, { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import { Key, User, Sun, Moon, Shield } from 'lucide-react';

interface LoginViewProps {
  onLoginSuccess: () => void;
}

const LoginView: React.FC<LoginViewProps> = ({ onLoginSuccess }) => {
  const { login } = useAuth();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  
  // Sincronizar el tema local para el toggle del login
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

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!username || !password) {
      setError('Por favor, complete todos los campos.');
      return;
    }

    setError(null);
    setIsSubmitting(true);

    try {
      const result = await login(username, password);
      if (result.success) {
        onLoginSuccess();
      } else {
        setError(result.error || 'Credenciales incorrectas.');
      }
    } catch (err) {
      setError('Error de red. No se pudo establecer conexión con la API de seguridad.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div style={styles.container}>
      <div style={styles.card}>
        {/* Toggle de Modo Claro / Modo Oscuro en la esquina del login */}
        <button
          onClick={toggleTheme}
          style={styles.themeToggle}
          title={theme === 'dark' ? 'Cambiar a Modo Claro' : 'Cambiar a Modo Oscuro'}
        >
          {theme === 'dark' ? <Sun size={12} /> : <Moon size={12} />}
        </button>

        <div style={styles.header}>
          <div style={styles.logoRow}>
            <div style={styles.logoIcon}>SPI</div>
            <span style={styles.logoText}>Core</span>
          </div>
          <h1 style={styles.title}>Iniciar sesión</h1>
          <p style={styles.subtitle}>Sincronización y aprovisionamiento ISP Carrier-Class</p>
        </div>

        {error && (
          <div style={styles.errorAlert}>
            <div style={{ fontWeight: 600, fontFamily: 'var(--font-mono)', fontSize: '11px', marginBottom: '2px' }}>ERROR_CODE_AUTH_FAIL</div>
            <div>{error}</div>
          </div>
        )}

        <form onSubmit={handleSubmit} style={styles.form}>
          <div style={styles.inputGroup}>
            <label htmlFor="username" style={styles.label}>Usuario de red</label>
            <div style={styles.inputWrapper}>
              <User size={13} style={styles.inputIcon} />
              <input
                id="username"
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="Ej: operador_admin"
                disabled={isSubmitting}
                style={styles.input}
              />
            </div>
          </div>

          <div style={styles.inputGroup}>
            <label htmlFor="password" style={styles.label}>Contraseña encriptada</label>
            <div style={styles.inputWrapper}>
              <Key size={13} style={styles.inputIcon} />
              <input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                disabled={isSubmitting}
                style={styles.input}
              />
            </div>
          </div>

          <button
            type="submit"
            disabled={isSubmitting}
            style={{
              ...styles.submitButton,
              opacity: isSubmitting ? 0.6 : 1,
              cursor: isSubmitting ? 'not-allowed' : 'pointer',
            }}
          >
            {isSubmitting ? (
              <span className="tech-mono">Autenticando...</span>
            ) : (
              'Ingresar al panel'
            )}
          </button>
        </form>

        <div style={styles.footer}>
          <Shield size={11} />
          <span>FIPS 140-2 Compliance • SSL/TLS Active</span>
        </div>
      </div>
    </div>
  );
};

// =========================================================================
// SISTEMA DE DISEÑO INTERNO - MODERN TECHNICAL / DENSE MINIMALIST
// =========================================================================
const styles: { [key: string]: React.CSSProperties } = {
  container: {
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    minHeight: '100vh',
    width: '100vw',
    position: 'fixed',
    top: 0,
    left: 0,
    backgroundColor: 'var(--bg-primary)',
    fontFamily: 'var(--font-inter)',
    overflow: 'hidden',
    zIndex: 99999,
    /* Sutil grilla milimétrica técnica de fondo */
    backgroundSize: '24px 24px',
    backgroundImage: `linear-gradient(to right, rgba(255, 255, 255, 0.005) 1px, transparent 1px),
                      linear-gradient(to bottom, rgba(255, 255, 255, 0.005) 1px, transparent 1px)`,
  },
  card: {
    position: 'relative',
    width: '100%',
    maxWidth: '360px', /* Más compacto y centrado */
    padding: '24px',    /* Menos padding (Density) */
    backgroundColor: 'var(--bg-secondary)',
    border: '1px solid var(--border-color)',
    borderRadius: '0px', /* Ángulos estrictos */
    display: 'flex',
    flexDirection: 'column',
    boxSizing: 'border-box',
    boxShadow: 'none',   /* Eliminación de sombras difusas */
  },
  themeToggle: {
    position: 'absolute',
    top: '12px',
    right: '12px',
    background: 'none',
    border: '1px solid var(--border-color)',
    color: 'var(--text-muted)',
    width: '24px',
    height: '24px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    cursor: 'pointer',
    borderRadius: '0px',
    transition: 'all 0.12s ease',
    outline: 'none',
  },
  header: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'flex-start', /* Alineado a la izquierda como Vercel/Linear */
    marginBottom: '20px',
    textAlign: 'left',
  },
  logoRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    marginBottom: '14px',
  },
  logoIcon: {
    padding: '2px 6px',
    borderRadius: '0px',
    backgroundColor: 'var(--text-main)',
    color: 'var(--bg-primary)',
    fontWeight: 'bold',
    fontSize: '11px',
    fontFamily: 'var(--font-mono)',
    letterSpacing: '0.5px',
  },
  logoText: {
    fontFamily: 'var(--font-mono)',
    fontSize: '11px',
    color: 'var(--text-muted)',
    fontWeight: 500,
  },
  title: {
    color: 'var(--text-main)',
    fontSize: '16px',
    fontWeight: 600,
    margin: '0 0 4px 0',
    letterSpacing: '-0.3px',
  },
  subtitle: {
    color: 'var(--text-muted)',
    fontSize: '12px',
    margin: 0,
    lineHeight: 1.4,
  },
  errorAlert: {
    backgroundColor: 'rgba(239, 68, 68, 0.04)',
    border: '1px solid rgba(239, 68, 68, 0.2)',
    color: '#ef4444',
    padding: '10px 12px',
    borderRadius: '0px',
    fontSize: '11px',
    lineHeight: 1.4,
    marginBottom: '16px',
    display: 'flex',
    flexDirection: 'column',
  },
  form: {
    display: 'flex',
    flexDirection: 'column',
    gap: '14px',
  },
  inputGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: '6px',
  },
  label: {
    color: 'var(--text-muted)',
    fontSize: '12px',
    fontWeight: 400,
  },
  inputWrapper: {
    position: 'relative',
    display: 'flex',
    alignItems: 'center',
  },
  inputIcon: {
    position: 'absolute',
    left: '10px',
    color: 'var(--text-muted)',
    pointerEvents: 'none',
  },
  input: {
    width: '100%',
    padding: '6px 10px 6px 30px', /* Súper compacto */
    borderRadius: '0px',
    backgroundColor: 'var(--bg-primary)',
    border: '1px solid var(--border-color)',
    color: 'var(--text-main)',
    fontFamily: 'var(--font-mono)', /* Fuente técnica */
    fontSize: '12px',
    outline: 'none',
    transition: 'all 0.12s ease',
    boxSizing: 'border-box',
  },
  submitButton: {
    width: '100%',
    padding: '8px 12px',
    borderRadius: '0px',
    backgroundColor: 'var(--accent-blue)',
    color: 'var(--text-dark)',
    fontSize: '12px',
    fontWeight: 500,
    border: '1px solid var(--accent-blue)',
    transition: 'all 0.12s ease',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: '6px',
    fontFamily: 'var(--font-inter)',
  },
  footer: {
    marginTop: '20px',
    paddingTop: '12px',
    borderTop: '1px solid var(--border-color)',
    textAlign: 'center',
    fontSize: '11px',
    color: 'var(--text-muted)',
    fontFamily: 'var(--font-mono)',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    gap: '6px',
  },
};

// Inyectar comportamientos e interacciones nativas de foco
if (typeof document !== 'undefined') {
  const styleSheet = document.createElement('style');
  styleSheet.type = 'text/css';
  styleSheet.innerText = `
    input:focus {
      border-color: var(--border-active) !important;
      background-color: var(--bg-tertiary) !important;
    }
    button:hover {
      filter: brightness(0.9);
    }
  `;
  document.head.appendChild(styleSheet);
}

export default LoginView;
