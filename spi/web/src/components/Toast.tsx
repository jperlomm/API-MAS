import React, { useEffect } from 'react';
import { ShieldAlert, CheckCircle, Info, X } from 'lucide-react';

interface ToastProps {
  message: string;
  type: 'success' | 'error' | 'info';
  onClose: () => void;
}

export const Toast: React.FC<ToastProps> = ({ message, type, onClose }) => {
  // Auto-close success and info after 4.5 seconds.
  // For errors, we DO NOT auto-close so the operator can read it carefully and must click "Entendido"!
  useEffect(() => {
    if (type !== 'error') {
      const timer = setTimeout(() => {
        onClose();
      }, 4500);
      return () => clearTimeout(timer);
    }
  }, [type, onClose]);

  const injectKeyframes = () => {
    return (
      <style>{`
        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @keyframes scaleUp {
          from { transform: scale(0.92); opacity: 0; }
          to { transform: scale(1); opacity: 1; }
        }
        @keyframes slideDown {
          from { transform: translate(-50%, -40px); opacity: 0; }
          to { transform: translate(-50%, 0); opacity: 1; }
        }
        @keyframes pulseGlow {
          0% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.4); }
          70% { box-shadow: 0 0 0 12px rgba(239, 68, 68, 0); }
          100% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0); }
        }
      `}</style>
    );
  };

  if (type === 'error') {
    // RENDER A STUNNING CENTERED ERROR MODAL WITH BACKDROP
    return (
      <div 
        style={{
          position: 'fixed',
          top: 0,
          left: 0,
          width: '100vw',
          height: '100vh',
          backgroundColor: 'rgba(0, 0, 0, 0.7)',
          backdropFilter: 'blur(3px)',
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          zIndex: 99999,
          animation: 'fadeIn 0.2s ease-out'
        }}
        onClick={onClose}
      >
        {injectKeyframes()}
        <div 
          style={{
            background: 'var(--bg-secondary, #18181b)',
            border: '2px solid #ef4444',
            boxShadow: '0 0 35px rgba(239, 68, 68, 0.22), 0 20px 25px -5px rgba(0,0,0,0.5)',
            borderRadius: '12px',
            width: '90%',
            maxWidth: '480px',
            padding: '32px',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: '20px',
            textAlign: 'center',
            position: 'relative',
            animation: 'scaleUp 0.25s cubic-bezier(0.34, 1.56, 0.64, 1) forwards'
          }}
          onClick={(e) => e.stopPropagation()} // Prevent closing when clicking inside card
        >
          {/* Close button at corner */}
          <button 
            onClick={onClose}
            style={{
              position: 'absolute',
              top: '16px',
              right: '16px',
              background: 'none',
              border: 'none',
              color: 'var(--text-muted, #71717a)',
              cursor: 'pointer',
              padding: '4px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center'
            }}
          >
            <X size={18} />
          </button>

          {/* Animated Glowing Error Shield */}
          <div style={{
            background: 'rgba(239, 68, 68, 0.1)',
            color: '#ef4444',
            padding: '16px',
            borderRadius: '50%',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            animation: 'pulseGlow 2s infinite'
          }}>
            <ShieldAlert size={36} />
          </div>

          <div>
            <h3 style={{ margin: '0 0 10px 0', fontSize: '18px', fontWeight: '700', color: 'var(--text-main, #fff)' }}>
              Acción Bloqueada / Alerta
            </h3>
            <p style={{ margin: 0, fontSize: '13.5px', lineHeight: '1.6', color: 'var(--text-muted, #71717a)', fontWeight: '400' }}>
              {message}
            </p>
          </div>

          <button 
            onClick={onClose}
            className="btn btn-primary"
            style={{ 
              width: '100%', 
              background: '#ef4444', 
              border: '1px solid #ef4444',
              color: '#fff',
              padding: '10px',
              fontSize: '13px',
              fontWeight: '600',
              borderRadius: '6px',
              cursor: 'pointer',
              boxShadow: '0 4px 12px rgba(239, 68, 68, 0.15)',
              marginTop: '8px',
              transition: 'all 0.2s'
            }}
            onMouseEnter={(e) => { e.currentTarget.style.background = '#dc2626'; }}
            onMouseLeave={(e) => { e.currentTarget.style.background = '#ef4444'; }}
          >
            Entendido
          </button>
        </div>
      </div>
    );
  }

  // RENDER A STUNNING CENTERED TOP CARD FOR SUCCESS / INFO
  const isSuccess = type === 'success';
  return (
    <div 
      style={{
        position: 'fixed',
        top: '24px',
        left: '50%',
        transform: 'translateX(-50%)',
        zIndex: 99999,
        display: 'flex',
        justifyContent: 'center',
        width: 'auto',
        minWidth: '320px',
        maxWidth: '90%',
        animation: 'slideDown 0.3s cubic-bezier(0.16, 1, 0.3, 1) forwards'
      }}
    >
      {injectKeyframes()}
      <div 
        style={{
          background: 'var(--bg-secondary, rgba(30, 41, 59, 0.95))',
          backdropFilter: 'blur(8px)',
          border: `1px solid ${isSuccess ? 'var(--success, #22c55e)' : 'var(--accent-cyan, #38bdf8)'}`,
          boxShadow: `0 10px 25px -5px rgba(0,0,0,0.15), 0 0 15px ${isSuccess ? 'rgba(34,197,94,0.1)' : 'rgba(56,189,248,0.1)'}`,
          borderRadius: '8px',
          padding: '12px 18px',
          display: 'flex',
          alignItems: 'center',
          gap: '12px',
          color: 'var(--text-main, #fff)',
          fontSize: '12.5px',
          fontWeight: '500'
        }}
      >
        <div style={{
          color: isSuccess ? 'var(--success, #22c55e)' : 'var(--accent-cyan, #38bdf8)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center'
        }}>
          {isSuccess ? <CheckCircle size={16} /> : <Info size={16} />}
        </div>
        <span style={{ flexGrow: 1, color: 'var(--text-main)' }}>{message}</span>
        <button 
          onClick={onClose}
          style={{
            background: 'none',
            border: 'none',
            color: 'var(--text-muted, #71717a)',
            cursor: 'pointer',
            padding: '2px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            opacity: 0.7
          }}
          onMouseEnter={(e) => { e.currentTarget.style.opacity = '1'; }}
          onMouseLeave={(e) => { e.currentTarget.style.opacity = '0.7'; }}
        >
          <X size={14} />
        </button>
      </div>
    </div>
  );
};

export default Toast;
