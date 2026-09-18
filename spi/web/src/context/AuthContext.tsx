import React, { createContext, useContext, useState, useEffect } from 'react';
import { apiFetch, setAccessToken, LoggedUser } from '../utils/api';

interface AuthContextType {
  user: LoggedUser | null;
  isAuthenticated: boolean;
  loading: boolean;
  login: (username: string, password: string) => Promise<{ success: boolean; error?: string }>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<LoggedUser | null>(null);
  const [loading, setLoading] = useState(true);

  // Intentar refresco silente al iniciar la aplicación para recuperar la sesión
  useEffect(() => {
    const initializeAuth = async () => {
      try {
        const response = await apiFetch<any>('/api/auth/refresh', { method: 'POST' });
        if (response.success && response.data?.accessToken) {
          setAccessToken(response.data.accessToken);
          
          // Obtener los datos del perfil
          const profileResponse = await apiFetch<LoggedUser>('/api/auth/profile');
          if (profileResponse.success && profileResponse.data) {
            setUser(profileResponse.data);
          } else {
            setAccessToken(null);
          }
        }
      } catch (err) {
        console.error('Error inicializando autenticación:', err);
      } finally {
        setLoading(false);
      }
    };

    initializeAuth();

    // Escuchar el evento de cierre de sesión forzado desde apiFetch
    const handleForceLogout = () => {
      setUser(null);
      setAccessToken(null);
    };

    window.addEventListener('auth-logout', handleForceLogout);
    return () => {
      window.removeEventListener('auth-logout', handleForceLogout);
    };
  }, []);

  const login = async (username: string, password: string) => {
    const response = await apiFetch<any>('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    });

    if (response.success && response.data) {
      const { accessToken, username: uName, nombreCompleto, email, rol } = response.data;
      setAccessToken(accessToken);
      const loggedInUser: LoggedUser = {
        id: '', // Se hidratará desde el profile si es necesario, o se usa el payload directo
        username: uName,
        nombreCompleto,
        email,
        rol,
      };
      setUser(loggedInUser);
      return { success: true };
    }

    return { success: false, error: response.error };
  };

  const logout = async () => {
    await apiFetch('/api/auth/logout', { method: 'POST' });
    setAccessToken(null);
    setUser(null);
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        isAuthenticated: !!user,
        loading,
        login,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth debe ser utilizado dentro de un AuthProvider');
  }
  return context;
};
