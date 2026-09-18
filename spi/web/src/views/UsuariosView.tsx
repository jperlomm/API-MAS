import React, { useState, useEffect } from 'react';
import { Plus, Search, Edit, Shield, UserCheck, UserX, KeyRound, Mail, User } from 'lucide-react';
import { apiFetch } from '../utils/api';

interface UserResponse {
  id: string;
  username: string;
  nombreCompleto: string;
  email: string;
  rol: string;
  activo: boolean;
  fechaCreacion: string;
}

interface UsuariosViewProps {
  showToast: (message: string, type?: 'success' | 'error' | 'info') => void;
}

export const UsuariosView: React.FC<UsuariosViewProps> = ({ showToast }) => {
  const [users, setUsers] = useState<UserResponse[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [search, setSearch] = useState<string>('');

  // Form states
  const [username, setUsername] = useState<string>('');
  const [password, setPassword] = useState<string>('');
  const [nombreCompleto, setNombreCompleto] = useState<string>('');
  const [email, setEmail] = useState<string>('');
  const [rol, setRol] = useState<string>('OPERADOR');
  const [activo, setActivo] = useState<boolean>(true);

  // Edit states
  const [editingUserId, setEditingUserId] = useState<string | null>(null);

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = async () => {
    setLoading(true);
    const res = await apiFetch<UserResponse[]>('/api/usuarios');
    if (res.success && res.data) {
      setUsers(res.data);
    } else {
      showToast(res.error || 'No se pudieron recuperar los operadores del sistema.', 'error');
    }
    setLoading(false);
  };

  const handleResetForm = () => {
    setEditingUserId(null);
    setUsername('');
    setPassword('');
    setNombreCompleto('');
    setEmail('');
    setRol('OPERADOR');
    setActivo(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!nombreCompleto || !email || !rol) {
      showToast('Por favor, complete todos los campos requeridos.', 'error');
      return;
    }

    if (!editingUserId) {
      // Crear nuevo usuario
      if (!username || !password) {
        showToast('El nombre de usuario y la contraseña son obligatorios.', 'error');
        return;
      }

      const res = await apiFetch('/api/usuarios', {
        method: 'POST',
        body: JSON.stringify({ username, password, nombreCompleto, email, rol }),
      });

      if (res.success) {
        showToast('Operador registrado con éxito en la plataforma.', 'success');
        handleResetForm();
        fetchUsers();
      } else {
        showToast(res.error || 'Error al registrar operador.', 'error');
      }
    } else {
      // Actualizar usuario existente
      const res = await apiFetch(`/api/usuarios/${editingUserId}`, {
        method: 'PUT',
        body: JSON.stringify({
          nombreCompleto,
          email,
          rol,
          activo,
          password: password || undefined, // Mandar solo si se completó
        }),
      });

      if (res.success) {
        showToast('Datos del operador actualizados correctamente.', 'success');
        handleResetForm();
        fetchUsers();
      } else {
        showToast(res.error || 'Error al actualizar los datos del operador.', 'error');
      }
    }
  };

  const handleEditClick = (user: UserResponse) => {
    setEditingUserId(user.id);
    setUsername(user.username);
    setPassword(''); // No mostrar la clave actual por seguridad
    setNombreCompleto(user.nombreCompleto);
    setEmail(user.email);
    setRol(user.rol);
    setActivo(user.activo);

    // Scroll suave hacia el formulario
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const handleToggleActivo = async (user: UserResponse) => {
    const confirmation = window.confirm(
      `¿Está seguro de que desea ${user.activo ? 'desactivar' : 'activar'} al operador ${user.nombreCompleto}?`
    );

    if (!confirmation) return;

    const res = await apiFetch(`/api/usuarios/${user.id}`, {
      method: 'PUT',
      body: JSON.stringify({
        nombreCompleto: user.nombreCompleto,
        email: user.email,
        rol: user.rol,
        activo: !user.activo,
      }),
    });

    if (res.success) {
      showToast(
        `Operador ${!user.activo ? 'activado' : 'desactivado'} con éxito.`,
        'success'
      );
      fetchUsers();
    } else {
      showToast(res.error || 'No se pudo alterar el estado de acceso del operador.', 'error');
    }
  };

  const filteredUsers = users.filter(
    (u) =>
      u.username.toLowerCase().includes(search.toLowerCase()) ||
      u.nombreCompleto.toLowerCase().includes(search.toLowerCase()) ||
      u.email.toLowerCase().includes(search.toLowerCase()) ||
      u.rol.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="view-container">
      <div className="view-header">
        <h2 style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <Shield style={{ color: '#6366f1' }} /> Personal y Seguridad de Red
        </h2>
        <p>Alta, edición y desactivación de operadores de aprovisionamiento en la plataforma.</p>
      </div>

      <div className="grid-2col">
        {/* Formulario de Alta / Edición */}
        <div className="panel-card">
          <div className="panel-title">
            <h3>{editingUserId ? 'Editar Operador' : 'Registrar Nuevo Operador'}</h3>
            {editingUserId && (
              <button className="btn-secondary btn-small" onClick={handleResetForm}>
                Cancelar
              </button>
            )}
          </div>

          <form onSubmit={handleSubmit} className="form-container">
            <div className="form-group">
              <label>Nombre de Usuario (Red)</label>
              <div className="input-with-icon">
                <User size={16} />
                <input
                  type="text"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  disabled={!!editingUserId}
                  placeholder="ej. jgomez"
                  required
                />
              </div>
            </div>

            <div className="form-group">
              <label>Nombre Completo</label>
              <div className="input-with-icon">
                <User size={16} />
                <input
                  type="text"
                  value={nombreCompleto}
                  onChange={(e) => setNombreCompleto(e.target.value)}
                  placeholder="ej. Juan Gómez"
                  required
                />
              </div>
            </div>

            <div className="form-group">
              <label>Correo Electrónico Corporativo</label>
              <div className="input-with-icon">
                <Mail size={16} />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="ej. jgomez@spi-network.net"
                  required
                />
              </div>
            </div>

            <div className="form-group">
              <label>Rol y Atribuciones de Acceso</label>
              <select value={rol} onChange={(e) => setRol(e.target.value)} required>
                <option value="OPERADOR">OPERADOR (Gestión de Servicios y Clientes)</option>
                <option value="ADMIN">ADMINISTRADOR (Acceso de Seguridad y ABM Total)</option>
                <option value="TECNICO">TÉCNICO (Solo lectura / Verificación de Equipos)</option>
              </select>
            </div>

            <div className="form-group">
              <label>
                {editingUserId
                  ? 'Cambiar Contraseña (Opcional)'
                  : 'Contraseña de Acceso'}
              </label>
              <div className="input-with-icon">
                <KeyRound size={16} />
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder={editingUserId ? 'Dejar vacío para no cambiar' : 'Mínimo 6 caracteres'}
                  required={!editingUserId}
                />
              </div>
            </div>

            {editingUserId && (
              <div className="form-group" style={{ flexDirection: 'row', gap: '8px', alignItems: 'center' }}>
                <input
                  id="activo-chk"
                  type="checkbox"
                  checked={activo}
                  onChange={(e) => setActivo(e.target.checked)}
                  style={{ width: 'auto', cursor: 'pointer' }}
                />
                <label htmlFor="activo-chk" style={{ cursor: 'pointer', margin: 0 }}>
                  Acceso habilitado al sistema (Activo)
                </label>
              </div>
            )}

            <button type="submit" className="btn-primary">
              <Plus size={16} style={{ marginRight: '6px' }} />
              {editingUserId ? 'Guardar Cambios' : 'Registrar Operador'}
            </button>
          </form>
        </div>

        {/* Tabla de Usuarios Registrados */}
        <div className="panel-card">
          <div className="panel-title">
            <h3>Lista de Personal Activo</h3>
            <div className="search-box">
              <Search size={16} />
              <input
                type="text"
                placeholder="Buscar por usuario, nombre, rol..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
          </div>

          {loading ? (
            <div style={{ textAlign: 'center', padding: '40px', color: '#64748b' }}>
              Cargando operadores del sistema...
            </div>
          ) : filteredUsers.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '40px', color: '#64748b' }}>
              No se encontraron operadores registrados.
            </div>
          ) : (
            <div className="table-responsive">
              <table>
                <thead>
                  <tr>
                    <th>Operador</th>
                    <th>Email</th>
                    <th>Rol</th>
                    <th>Estado</th>
                    <th>Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredUsers.map((u) => {
                    const rolColors: { [key: string]: { bg: string; color: string } } = {
                      ADMIN: { bg: 'rgba(239, 68, 68, 0.1)', color: '#ef4444' },
                      OPERADOR: { bg: 'rgba(99, 102, 241, 0.1)', color: '#6366f1' },
                      TECNICO: { bg: 'rgba(245, 158, 11, 0.1)', color: '#f59e0b' },
                    };
                    const color = rolColors[u.rol] || { bg: 'rgba(255,255,255,0.05)', color: '#ffffff' };

                    return (
                      <tr key={u.id}>
                        <td>
                          <div style={{ fontWeight: 'bold', color: '#f8fafc' }}>{u.nombreCompleto}</div>
                          <div style={{ fontSize: '12px', color: '#64748b' }}>@{u.username}</div>
                        </td>
                        <td>{u.email}</td>
                        <td>
                          <span
                            style={{
                              padding: '2px 8px',
                              borderRadius: '4px',
                              fontSize: '11px',
                              fontWeight: 'bold',
                              backgroundColor: color.bg,
                              color: color.color,
                            }}
                          >
                            {u.rol}
                          </span>
                        </td>
                        <td>
                          <span
                            style={{
                              padding: '2px 8px',
                              borderRadius: '4px',
                              fontSize: '11px',
                              fontWeight: 'bold',
                              backgroundColor: u.activo ? 'rgba(34, 197, 94, 0.1)' : 'rgba(100, 116, 139, 0.1)',
                              color: u.activo ? '#22c55e' : '#64748b',
                            }}
                          >
                            {u.activo ? 'ACTIVO' : 'INACTIVO'}
                          </span>
                        </td>
                        <td>
                          <div style={{ display: 'flex', gap: '8px' }}>
                            <button
                              className="btn-icon"
                              title="Editar Operador"
                              onClick={() => handleEditClick(u)}
                            >
                              <Edit size={14} />
                            </button>
                            <button
                              className="btn-icon"
                              title={u.activo ? 'Desactivar Acceso' : 'Activar Acceso'}
                              onClick={() => handleToggleActivo(u)}
                              style={{ color: u.activo ? '#f87171' : '#4ade80' }}
                            >
                              {u.activo ? <UserX size={14} /> : <UserCheck size={14} />}
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default UsuariosView;
