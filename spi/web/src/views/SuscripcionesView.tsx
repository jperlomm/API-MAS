import React, { useState, useEffect } from 'react';
import { Zap, Plus, Trash2, Power, PowerOff, ShieldAlert, Cpu, Edit2, X, Search } from 'lucide-react';
import { apiFetch, Servicio, Cliente, Equipo, Paquete, CMTS } from '../utils/api';

interface SuscripcionesViewProps {
  showToast: (msg: string, type: 'success' | 'error') => void;
}

export const SuscripcionesView: React.FC<SuscripcionesViewProps> = ({ showToast }) => {
  const [servicios, setServicios] = useState<Servicio[]>([]);
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [equiposInStock, setEquiposInStock] = useState<Equipo[]>([]);
  const [paquetes, setPaquetes] = useState<Paquete[]>([]);
  const [cmtsList, setCmtsList] = useState<CMTS[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [editingId, setEditingId] = useState<number | null>(null);

  // Search and pagination states
  const [search, setSearch] = useState<string>('');
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [itemsPerPage, setItemsPerPage] = useState<number>(10);

  // Reset page when search term changes
  useEffect(() => {
    setCurrentPage(1);
  }, [search, itemsPerPage]);

  const [idCliente, setIdCliente] = useState<string>('');
  const [idEquipo, setIdEquipo] = useState<string>('');
  const [idPaquete, setIdPaquete] = useState<string>('');
  const [idCmts, setIdCmts] = useState<string>('');
  const [ipCm, setIpCm] = useState<string>('');
  const [ipCpe, setIpCpe] = useState<string>('');
  const [direccionInstalacion, setDireccionInstalacion] = useState<string>('');

  // Bulk operation states
  const [bulkCodigosInput, setBulkCodigosInput] = useState<string>('');

  const loadData = async (currentEditingEquipoId?: number) => {
    setLoading(true);
    const resSer = await apiFetch<Servicio[]>('/api/servicios');
    const resCli = await apiFetch<Cliente[]>('/api/clientes');
    const resEq = await apiFetch<Equipo[]>('/api/equipos');
    const resPaq = await apiFetch<Paquete[]>('/api/red/paquetes');
    const resCmts = await apiFetch<CMTS[]>('/api/red/cmts');

    if (resSer.success && resSer.data) setServicios(resSer.data);
    if (resCli.success && resCli.data) setClientes(resCli.data);
    if (resPaq.success && resPaq.data) setPaquetes(resPaq.data);
    if (resCmts.success && resCmts.data) setCmtsList(resCmts.data);

    // Filtrar equipos que estén en stock o que sean el actual en edición (así se muestra seleccionado en el form)
    if (resEq.success && resEq.data) {
      setEquiposInStock(resEq.data.filter(e => e.estado === 'INVENTARIO' || e.id === currentEditingEquipoId));
    }

    if (!resSer.success) {
      showToast('Error de red al actualizar suscripciones.', 'error');
    }
    setLoading(false);
  };

  useEffect(() => {
    loadData();
  }, []);

  const handleStartEdit = (s: Servicio) => {
    setEditingId(s.id || null);
    setIdCliente(s.idCliente?.toString() ?? '');
    setIdEquipo(s.idEquipo?.toString() ?? '');
    setIdPaquete(s.idPaquete?.toString() ?? '');
    setIdCmts(s.idCmts?.toString() ?? '');
    setIpCm(s.ipCm || '');
    setIpCpe(s.ipCpe || '');
    setDireccionInstalacion(s.direccionInstalacion || '');
    
    // Recargar datos para forzar que el equipo asignado actualmente aparezca en la lista de opciones seleccionables
    loadData(s.idEquipo);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const handleCancelEdit = () => {
    setEditingId(null);
    setIdCliente('');
    setIdEquipo('');
    setIdPaquete('');
    setIdCmts('');
    setIpCm('');
    setIpCpe('');
    setDireccionInstalacion('');
    loadData();
  };

  const handleAutoAssignCm = async () => {
    if (!idCmts) {
      showToast('Debe seleccionar un CMTS primero para autocompletar la IP de gestión.', 'error');
      return;
    }
    const res = await apiFetch<{ ip: string }>(`/api/ipam/next-free-ip?idCmts=${idCmts}&tipo=CM`);
    if (res.success && res.data) {
      setIpCm(res.data.ip);
      showToast(`IP de Gestión ${res.data.ip} sugerida y reservada por 5 minutos.`, 'success');
    } else {
      showToast(res.error || 'No se pudo obtener una IP libre de gestión.', 'error');
    }
  };

  const handleAutoAssignCpe = async () => {
    if (!idCmts) {
      showToast('Debe seleccionar un CMTS primero para autocompletar la IP de ruteo.', 'error');
      return;
    }
    const url = `/api/ipam/next-free-ip?idCmts=${idCmts}&tipo=CPE${idPaquete ? `&idPaquete=${idPaquete}` : ''}`;
    const res = await apiFetch<{ ip: string }>(url);
    if (res.success && res.data) {
      setIpCpe(res.data.ip);
      showToast(`IP de Navegación ${res.data.ip} sugerida y reservada por 5 minutos.`, 'success');
    } else {
      showToast(res.error || 'No se pudo obtener una IP libre de ruteo.', 'error');
    }
  };

  const handleProvision = async (e: React.FormEvent) => {
    e.preventDefault();

    const payload: Servicio = {
      idCliente: parseInt(idCliente),
      idEquipo: parseInt(idEquipo),
      idPaquete: parseInt(idPaquete),
      idCmts: idCmts ? parseInt(idCmts) : undefined,
      ipCm: ipCm.trim() || null,
      ipCpe: ipCpe.trim() || null,
      direccionInstalacion: direccionInstalacion.trim() || null,
    };

    const endpoint = editingId ? `/api/servicios/${editingId}` : '/api/servicios';
    const method = editingId ? 'PUT' : 'POST';

    const res = await apiFetch(endpoint, {
      method,
      body: JSON.stringify(payload),
    });

    if (res.success) {
      showToast(res.data?.message || (editingId ? 'Suscripción técnica actualizada y re-sincronizada.' : 'Servicio activado e inyectado con éxito en Kea DHCP.'), 'success');
      setEditingId(null);
      setIdCliente('');
      setIdEquipo('');
      setIdPaquete('');
      setIdCmts('');
      setIpCm('');
      setIpCpe('');
      setDireccionInstalacion('');
      loadData();
    } else {
      showToast(res.error || 'No se pudo procesar la suscripción.', 'error');
    }
  };

  const handleToggleEstado = async (id: number, estadoActual?: 'ACTIVO' | 'SUSPENDIDO') => {
    const accion = estadoActual === 'ACTIVO' ? 'suspender' : 'reactivar';
    const confirmacion = window.confirm(`¿Está seguro que desea ${accion} esta suscripción (ID: ${id})?`);
    if (!confirmacion) return;

    const endpoint = `/api/servicios/${id}/${accion}`;
    const res = await apiFetch(endpoint, {
      method: 'POST',
    });

    if (res.success) {
      showToast(res.data?.message || `Servicio ${estadoActual === 'ACTIVO' ? 'suspendido' : 'reactivado'}.`, 'success');
      loadData();
    } else {
      showToast(res.error || `No se pudo realizar el cambio de estado.`, 'error');
    }
  };

  const handleDeleteServicio = async (id: number) => {
    if (!window.confirm('¿Está seguro de eliminar esta suscripción? El equipo volverá a INVENTARIO y se borrará el lease de Kea.')) {
      return;
    }

    const res = await apiFetch(`/api/servicios/${id}`, {
      method: 'DELETE',
    });

    if (res.success) {
      showToast(res.data?.message || 'Suscripción dada de baja.', 'success');
      loadData();
    } else {
      showToast(res.error || 'No se pudo completar la baja.', 'error');
    }
  };

  const handleBulkOperation = async (action: 'suspend' | 'reactivate') => {
    const codes = bulkCodigosInput
      .split('\n')
      .map(c => c.trim())
      .filter(c => c.length > 0);

    if (codes.length === 0) {
      showToast('Debe ingresar al menos un código de facturación para realizar la operación masiva.', 'error');
      return;
    }

    const actionText = action === 'suspend' ? 'SUSPENDER' : 'REACTIVAR';
    const confirmacion = window.confirm(
      `¿CONFIRMA ${actionText} MASIVAMENTE a ${codes.length} abonados ingresados?\n\nEsta acción inyectará inmediatamente los cambios y encolará los reinicios SNMP.`
    );
    if (!confirmacion) return;

    const nuevoEstado = action === 'suspend' ? 'SUSPENDIDO' : 'ACTIVO';
    const res = await apiFetch('/api/servicios/bulk-estado-by-codigos', {
      method: 'POST',
      body: JSON.stringify({
        codigos: codes,
        nuevoEstado: nuevoEstado
      }),
    });

    if (res.success) {
      showToast(res.data?.message || `Operación de ${actionText} masiva completada con éxito.`, 'success');
      setBulkCodigosInput('');
      loadData();
    } else {
      showToast(res.error || 'Fallo al procesar operación masiva.', 'error');
    }
  };

  // Filtering logic
  const filteredServicios = servicios.filter(s => 
    (s.cliente || '').toLowerCase().includes(search.toLowerCase()) ||
    (s.equipoMac || '').toLowerCase().includes(search.toLowerCase()) ||
    (s.paquete || '').toLowerCase().includes(search.toLowerCase()) ||
    (s.ipCpe || '').toLowerCase().includes(search.toLowerCase()) ||
    (s.ipCm || '').toLowerCase().includes(search.toLowerCase()) ||
    (s.ipAsignada || '').toLowerCase().includes(search.toLowerCase()) ||
    (s.cmts || '').toLowerCase().includes(search.toLowerCase()) ||
    (s.id?.toString() || '').includes(search)
  );

  // Pagination calculations
  const totalItems = filteredServicios.length;
  const totalPages = Math.ceil(totalItems / itemsPerPage);
  const paginatedServicios = filteredServicios.slice(
    (currentPage - 1) * itemsPerPage,
    currentPage * itemsPerPage
  );

  // Helper to generate dynamic page numbers with ellipses
  const renderPageNumbers = () => {
    const pages: (number | string)[] = [];
    const range = 1; // Number of neighbors on each side
    
    for (let i = 1; i <= totalPages; i++) {
      if (i === 1 || i === totalPages || (i >= currentPage - range && i <= currentPage + range)) {
        pages.push(i);
      } else if (pages[pages.length - 1] !== '...') {
        pages.push('...');
      }
    }
    return pages;
  };

  return (
    <div>
      {/* 1. ACTIVACIÓN DE ENLACE */}
      <div className="panel" style={editingId ? { border: '1px solid var(--accent)', boxShadow: '0 0 12px rgba(14, 165, 233, 0.15)' } : undefined}>
        <div className="panel-header" style={editingId ? { borderColor: 'rgba(14, 165, 233, 0.2)' } : undefined}>
          <div className="panel-title" style={editingId ? { color: 'var(--accent)' } : undefined}>
            {editingId ? <Edit2 size={16} /> : <Plus size={16} />} 
            {editingId ? `Modificar Enlace Técnico (ID: ${editingId})` : 'Aprovisionar Nuevo Enlace de Fibra/Coaxial'}
          </div>
        </div>
        <form onSubmit={handleProvision}>
          <div className="form-grid">
            <div className="form-group">
              <label htmlFor="s-cli">Cliente (Abonado) *</label>
              <select id="s-cli" value={idCliente} onChange={e => setIdCliente(e.target.value)} required>
                <option value="">-- Seleccionar Abonado --</option>
                {clientes.map(c => <option key={c.id} value={c.id}>{c.razonSocial} (CUIT: {c.cuitDni})</option>)}
              </select>
              <small className="help-text">Tabla: <code>admin.clientes</code> | Campo: <code>id_cliente</code></small>
            </div>
            <div className="form-group">
              <label htmlFor="s-eq">Equipo Físico en Stock *</label>
              <select id="s-eq" value={idEquipo} onChange={e => setIdEquipo(e.target.value)} required>
                <option value="">-- Seleccionar Hardware Libre --</option>
                {equiposInStock.map(e => (
                  <option key={e.id} value={e.id}>
                    {e.modelo} [MAC: {e.mac}] {e.numeroSerie ? `(S/N: ${e.numeroSerie})` : ''}
                  </option>
                ))}
              </select>
              <small className="help-text">Tabla: <code>admin.equipos</code> | Campo: <code>id_equipo</code></small>
            </div>
            <div className="form-group">
              <label htmlFor="s-paq">Plan de Velocidad Asignado *</label>
              <select id="s-paq" value={idPaquete} onChange={e => setIdPaquete(e.target.value)} required>
                <option value="">-- Seleccionar Perfil de Velocidad --</option>
                {paquetes.map(p => (
                  <option key={p.id} value={p.id}>
                    {p.nombre} (Down: {(p.velocidadBajadaKbps / 1024).toFixed(0)}M / Up: {(p.velocidadSubidaKbps / 1024).toFixed(0)}M)
                  </option>
                ))}
              </select>
              <small className="help-text">Tabla: <code>admin.paquetes</code> | Campo: <code>id_paquete</code></small>
            </div>
            {/* El CMTS y las IPs estáticas fijas han sido completamente removidos del formulario.
                Se manejan automáticamente por red mediante Autodetección DHCP Reactiva en el primer ciclo de encendido. */}
            <div className="form-group" style={{ gridColumn: 'span 3' }}>
              <label htmlFor="s-dirinstalacion">Dirección de Instalación Específica</label>
              <input 
                id="s-dirinstalacion" 
                type="text" 
                placeholder="Dejar vacío para usar el domicilio fiscal del cliente" 
                value={direccionInstalacion} 
                onChange={e => setDireccionInstalacion(e.target.value)} 
                style={{ width: '100%' }}
              />
              <small className="help-text">Opcional. Si se deja en blanco se heredará la dirección principal del cliente. Tabla: <code>admin.servicios_clientes</code> | Campo: <code>direccion_instalacion</code></small>
            </div>
          </div>
          <div style={{ display: 'flex', gap: '12px', marginTop: '16px' }}>
            <button type="submit" className="btn btn-primary">
              {editingId ? 'Guardar Cambios del Enlace' : 'Activar y Energizar Enlace'}
            </button>
            {editingId && (
              <button type="button" className="btn btn-muted" onClick={handleCancelEdit} style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
                <X size={14} /> Cancelar Edición
              </button>
            )}
          </div>
        </form>
      </div>

      {/* 2. TABLA SERVICIOS */}
      <div className="panel">
        <div className="panel-header" style={{ borderBottom: 'none' }}>
          <div className="panel-title">
            <Zap size={16} /> Servicios y Leases DHCP Activos
          </div>
        </div>

        <div className="search-box" style={{ marginBottom: '16px', maxWidth: '400px', margin: '0 20px 16px 20px' }}>
          <Search size={16} />
          <input 
            type="text" 
            placeholder="Buscar por abonado, MAC, IP, CMTS o plan..." 
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        <div className="table-responsive">
          <table>
            <thead>
              <tr>
                <th style={{ width: '80px' }}>ID</th>
                <th>Abonado</th>
                <th>CMTS de Ruta</th>
                <th>MAC física</th>
                <th>Dirección IP (CPE / CM)</th>
                <th>Plan Asignado</th>
                <th>Estado de Red</th>
                <th>Fecha Activación</th>
                <th style={{ width: '220px', textAlign: 'center' }}>Acciones Operativas</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={9} style={{ textAlign: 'center', padding: '32px' }}>Cargando suscripciones...</td>
                </tr>
              ) : paginatedServicios.length === 0 ? (
                <tr>
                  <td colSpan={9} style={{ textAlign: 'center', opacity: 0.5, padding: '32px' }}>
                    {servicios.length === 0 ? "No hay enlaces activos en el sistema." : "No se encontraron enlaces que coincidan con la búsqueda."}
                  </td>
                </tr>
              ) : (
                paginatedServicios.map(s => (
                  <tr key={s.id}>
                    <td><strong>{s.id}</strong></td>
                    <td>
                      <div><strong>{s.cliente}</strong></div>
                      {s.direccionInstalacion ? (
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
                          📍 {s.direccionInstalacion}
                        </div>
                      ) : (
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)', opacity: 0.6, marginTop: '4px' }}>
                          🏠 (Domicilio Fiscal)
                        </div>
                      )}
                    </td>
                    <td>
                      {s.idCmts ? (
                        <span style={{ fontSize: '12px', opacity: 0.8 }}>⚙️ {s.cmts}</span>
                      ) : (
                        <span className="badge" style={{ 
                          backgroundColor: 'rgba(245, 158, 11, 0.1)', 
                          color: '#f59e0b', 
                          border: '1px solid rgba(245, 158, 11, 0.2)',
                          fontSize: '11px',
                          fontWeight: 600,
                          padding: '2px 8px'
                        }}>
                          ⏳ Autodetectando...
                        </span>
                      )}
                    </td>
                    <td><code>{s.equipoMac}</code></td>
                    <td>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                        {s.ipCpe ? (
                          <span className="badge" style={{ 
                            backgroundColor: 'rgba(14, 165, 233, 0.1)', 
                            color: 'var(--accent)', 
                            border: '1px solid rgba(14, 165, 233, 0.2)',
                            alignSelf: 'flex-start',
                            fontSize: '11px',
                            fontWeight: 600,
                            padding: '2px 8px'
                          }}>
                            📌 CPE Fija: {s.ipCpe}
                          </span>
                        ) : (
                          <span style={{ 
                            color: s.ipAsignada ? 'var(--success)' : 'var(--text-muted)',
                            fontWeight: s.ipAsignada ? 600 : 400,
                            fontSize: '12px'
                          }}>
                            🌐 CPE Dinámica: {s.ipAsignada || 'IP Dinámica'}
                          </span>
                        )}

                        {s.ipCm && (
                          <span style={{ 
                            fontSize: '11px', 
                            color: 'var(--text-muted)',
                            fontFamily: 'monospace'
                          }}>
                            📠 Gestión CM: {s.ipCm}
                          </span>
                        )}
                      </div>
                    </td>
                    <td>{s.paquete}</td>
                    <td>
                      <span className={`badge ${s.estado === 'ACTIVO' ? 'badge-active' : 'badge-suspended'}`}>
                        {s.estado}
                      </span>
                    </td>
                    <td>{s.fechaActivacion ? new Date(s.fechaActivacion).toLocaleDateString() : '-'}</td>
                    <td style={{ display: 'flex', gap: '8px', justifyContent: 'center' }}>
                      <button
                        onClick={() => handleStartEdit(s)}
                        className="btn"
                        style={{ 
                          padding: '6px 12px', 
                          display: 'flex', 
                          gap: '4px', 
                          alignItems: 'center', 
                          fontSize: '11px',
                          backgroundColor: 'rgba(14, 165, 233, 0.1)',
                          color: 'var(--accent)',
                          border: '1px solid rgba(14, 165, 233, 0.2)'
                        }}
                      >
                        <Edit2 size={11} />
                        Editar
                      </button>
                      <button
                        onClick={() => handleToggleEstado(s.id!, s.estado)}
                        className={`btn ${s.estado === 'ACTIVO' ? 'btn-warning' : 'btn-success'}`}
                        style={{ padding: '6px 12px', display: 'flex', gap: '4px', alignItems: 'center', fontSize: '11px' }}
                      >
                        {s.estado === 'ACTIVO' ? <PowerOff size={11} /> : <Power size={11} />}
                        {s.estado === 'ACTIVO' ? 'Suspender' : 'Reactivar'}
                      </button>
                      <button
                        onClick={() => handleDeleteServicio(s.id!)}
                        className="btn btn-danger"
                        style={{ padding: '6px 12px', display: 'flex', gap: '4px', alignItems: 'center', fontSize: '11px' }}
                      >
                        <Trash2 size={11} />
                        Baja
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {/* PAGINACIÓN PROFESIONAL */}
        {totalItems > 0 && (
          <div style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            marginTop: '20px',
            paddingTop: '20px',
            paddingBottom: '10px',
            borderTop: '1px solid var(--border-color)',
            flexWrap: 'wrap',
            gap: '12px',
            marginLeft: '20px',
            marginRight: '20px'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', fontSize: '13px', color: 'var(--text-muted)' }}>
              <span>
                Mostrando <strong>{(currentPage - 1) * itemsPerPage + 1}</strong> a{' '}
                <strong>{Math.min(currentPage * itemsPerPage, totalItems)}</strong> de{' '}
                <strong>{totalItems}</strong> enlaces
              </span>
              <select
                value={itemsPerPage}
                onChange={(e) => setItemsPerPage(parseInt(e.target.value))}
                style={{
                  padding: '4px 8px',
                  borderRadius: '4px',
                  backgroundColor: 'var(--bg-primary)',
                  border: '1px solid var(--border-color)',
                  color: 'var(--text-main)',
                  fontSize: '12px',
                  cursor: 'pointer'
                }}
              >
                <option value={10}>10 por pág.</option>
                <option value={25}>25 por pág.</option>
                <option value={50}>50 por pág.</option>
                <option value={100}>100 por pág.</option>
              </select>
            </div>
            
            <div style={{ display: 'flex', gap: '4px', alignItems: 'center' }}>
              <button
                type="button"
                onClick={() => setCurrentPage(prev => Math.max(prev - 1, 1))}
                disabled={currentPage === 1}
                className="btn"
                style={{ padding: '6px 12px', fontSize: '12px', opacity: currentPage === 1 ? 0.5 : 1 }}
              >
                « Anterior
              </button>
              
              {renderPageNumbers().map((p, idx) => (
                p === '...' ? (
                  <span key={`ellipsis-${idx}`} style={{ padding: '4px 8px', color: 'var(--text-muted)', fontSize: '12px' }}>...</span>
                ) : (
                  <button
                    key={`page-${p}`}
                    type="button"
                    onClick={() => setCurrentPage(p as number)}
                    className={`btn ${currentPage === p ? 'btn-primary' : 'btn-secondary'}`}
                    style={{
                      padding: '6px 12px',
                      fontSize: '12px',
                      minWidth: '36px',
                      backgroundColor: currentPage === p ? 'var(--accent)' : undefined
                    }}
                  >
                    {p}
                  </button>
                )
              ))}
              
              <button
                type="button"
                onClick={() => setCurrentPage(prev => Math.min(prev + 1, totalPages))}
                disabled={currentPage === totalPages}
                className="btn"
                style={{ padding: '6px 12px', fontSize: '12px', opacity: currentPage === totalPages ? 0.5 : 1 }}
              >
                Siguiente »
              </button>
            </div>
          </div>
        )}
      </div>

      {/* 3. OPERACIONES MASIVAS */}
      <div className="panel" style={{ border: '1px solid var(--danger)', backgroundColor: 'rgba(244, 63, 94, 0.01)' }}>
        <div className="panel-header" style={{ borderColor: 'rgba(244, 63, 94, 0.2)' }}>
          <div className="panel-title" style={{ color: 'var(--danger)' }}>
            <ShieldAlert size={18} /> Consola de Operaciones de Corte Masivo (Mora de Pago)
          </div>
        </div>
        <p className="bulk-desc">
          Esta consola inyecta configuraciones masivas en la base de datos de Kea DHCP. Permite aplicar suspensiones o reactivaciones de forma masiva a partir de un listado de códigos de facturación de abonados (uno por línea). Use con extrema precaución.
        </p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          <div className="form-group" style={{ width: '100%' }}>
            <label style={{ color: 'var(--text-main)', fontWeight: 'bold' }}>
              Listado de Códigos de Facturación (Ingrese un código por línea o cópielo directamente de su planilla)
            </label>
            <textarea
              rows={6}
              value={bulkCodigosInput}
              onChange={e => setBulkCodigosInput(e.target.value)}
              placeholder="Ejemplo:&#10;AB-4921&#10;AB-1052&#10;AB-8841"
              style={{
                width: '100%',
                fontFamily: 'var(--font-mono)',
                fontSize: '12px',
                padding: '10px',
                backgroundColor: 'var(--bg-primary)',
                border: '1px solid var(--border-color)',
                color: 'var(--text-main)',
                resize: 'vertical'
              }}
            />
          </div>
          <div style={{ display: 'flex', gap: '12px', justifyContent: 'flex-end' }}>
            <button 
              onClick={() => handleBulkOperation('suspend')} 
              className="btn btn-danger"
              style={{ padding: '10px 20px', fontWeight: 'bold', display: 'flex', gap: '6px', alignItems: 'center' }}
            >
              <PowerOff size={14} /> Corte Masivo de Red
            </button>
            <button 
              onClick={() => handleBulkOperation('reactivate')} 
              className="btn btn-success"
              style={{ padding: '10px 20px', fontWeight: 'bold', display: 'flex', gap: '6px', alignItems: 'center' }}
            >
              <Power size={14} /> Habilitar de Pago (Reactivar)
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default SuscripcionesView;
