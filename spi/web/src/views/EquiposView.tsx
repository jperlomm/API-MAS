import React, { useState, useEffect } from 'react';
import { Cpu, Plus, Trash2, ShieldAlert, Edit, Search } from 'lucide-react';
import { apiFetch, Equipo, HardwareModelo, HardwareMarca } from '../utils/api';

interface EquiposViewProps {
  showToast: (msg: string, type: 'success' | 'error') => void;
}

export const EquiposView: React.FC<EquiposViewProps> = ({ showToast }) => {
  // Catalogs
  const [equipos, setEquipos] = useState<Equipo[]>([]);
  const [modelos, setModelos] = useState<HardwareModelo[]>([]);
  const [marcas, setMarcas] = useState<HardwareMarca[]>([]);
  const [loading, setLoading] = useState<boolean>(true);

  // Sub-tab de navegación interna
  const [activeSubTab, setActiveSubTab] = useState<'stock' | 'catalogo'>('stock');

  // Búsqueda y Paginación de Stock
  const [search, setSearch] = useState<string>('');
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [itemsPerPage, setItemsPerPage] = useState<number>(10);

  // Equipment Form
  const [idModelo, setIdModelo] = useState<string>('');
  const [mac, setMac] = useState<string>('');
  const [numeroSerie, setNumeroSerie] = useState<string>('');
  const [estado, setEstado] = useState<string>('INVENTARIO');

  // Editing state
  const [editingEquipoId, setEditingEquipoId] = useState<number | null>(null);

  // Model Form
  const [idMarcaModelo, setIdMarcaModelo] = useState<string>('');
  const [nombreModelo, setNombreModelo] = useState<string>('');
  const [tipoTecnologicoModelo, setTipoTecnologicoModelo] = useState<'DOCSIS' | 'GPON'>('DOCSIS');
  const [descripcionModelo, setDescripcionModelo] = useState<string>('');

  // Brand Form
  const [nombreMarca, setNombreMarca] = useState<string>('');

  const loadData = async () => {
    setLoading(true);
    const resEq = await apiFetch<Equipo[]>('/api/equipos');
    const resMod = await apiFetch<HardwareModelo[]>('/api/modelos');
    const resMarcas = await apiFetch<HardwareMarca[]>('/api/modelos/marcas');

    if (resEq.success && resEq.data) setEquipos(resEq.data);
    if (resMod.success && resMod.data) setModelos(resMod.data);
    if (resMarcas.success && resMarcas.data) setMarcas(resMarcas.data);

    if (!resEq.success || !resMod.success) {
      showToast('Error al cargar inventario o catálogos de hardware.', 'error');
    }
    setLoading(false);
  };

  useEffect(() => {
    loadData();
  }, []);

  // Reset de página al cambiar búsqueda o items por página
  useEffect(() => {
    setCurrentPage(1);
  }, [search, itemsPerPage]);

  const filteredEquipos = equipos.filter(e => 
    e.mac.toLowerCase().includes(search.toLowerCase()) ||
    (e.numeroSerie || '').toLowerCase().includes(search.toLowerCase()) ||
    (e.modelo || '').toLowerCase().includes(search.toLowerCase()) ||
    (e.estado || '').toLowerCase().includes(search.toLowerCase()) ||
    (e.tipoTecnologico || '').toLowerCase().includes(search.toLowerCase())
  );

  const totalItems = filteredEquipos.length;
  const totalPages = Math.ceil(totalItems / itemsPerPage);
  const paginatedEquipos = filteredEquipos.slice(
    (currentPage - 1) * itemsPerPage,
    currentPage * itemsPerPage
  );

  const renderPageNumbers = () => {
    const pages: (number | string)[] = [];
    const range = 1;
    for (let i = 1; i <= totalPages; i++) {
      if (i === 1 || i === totalPages || (i >= currentPage - range && i <= currentPage + range)) {
        pages.push(i);
      } else if (pages[pages.length - 1] !== '...') {
        pages.push('...');
      }
    }
    return pages;
  };

  const handleRegisterEquipo = async (e: React.FormEvent) => {
    e.preventDefault();

    const cleanMac = mac.trim();
    if (!cleanMac || cleanMac.toLowerCase() === 'string') {
      showToast('La dirección MAC física es obligatoria.', 'error');
      return;
    }

    // Validación Regex de MAC IEEE estándar (12 digitos hex, opcionalmente separados por : o -)
    const macRegex = /^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/;
    const macRegexPlain = /^[0-9A-Fa-f]{12}$/;
    if (!macRegex.test(cleanMac) && !macRegexPlain.test(cleanMac)) {
      showToast('La dirección MAC no tiene un formato hexadecimal válido (ej: 7C:B2:1B:A0:00:F6).', 'error');
      return;
    }

    const payload: Equipo = {
      idModelo: parseInt(idModelo),
      mac: cleanMac,
      numeroSerie: numeroSerie.trim() || null,
      estado: estado as any,
    };

    if (editingEquipoId) {
      const res = await apiFetch(`/api/equipos/${editingEquipoId}`, {
        method: 'PUT',
        body: JSON.stringify(payload),
      });

      if (res.success) {
        showToast(res.data?.message || 'Datos de equipo actualizados en Stock.', 'success');
        handleCancelEditEquipo();
        loadData();
      } else {
        showToast(res.error || 'No se pudo actualizar el equipo.', 'error');
      }
    } else {
      const res = await apiFetch('/api/equipos', {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      if (res.success) {
        showToast(res.data?.message || 'Equipo ingresado con éxito al Stock.', 'success');
        setIdModelo('');
        setMac('');
        setNumeroSerie('');
        loadData();
      } else {
        showToast(res.error || 'No se pudo ingresar el equipo.', 'error');
      }
    }
  };

  const handleEditEquipoClick = (eq: Equipo) => {
    setEditingEquipoId(eq.id!);
    setMac(eq.mac);
    setNumeroSerie(eq.numeroSerie || '');
    setEstado(eq.estado || 'INVENTARIO');
    
    // Buscar modelo por nombre para preseleccionar en el formulario
    const matched = modelos.find(m => m.nombre === eq.modelo);
    if (matched) {
      setIdModelo(String(matched.id));
    } else {
      setIdModelo('');
    }
  };

  const handleCancelEditEquipo = () => {
    setEditingEquipoId(null);
    setIdModelo('');
    setMac('');
    setNumeroSerie('');
    setEstado('INVENTARIO');
  };

  const handleDeleteEquipo = async (id: number) => {
    if (!window.confirm(`¿Está seguro que desea eliminar este equipo (ID: ${id}) del inventario?`)) {
      return;
    }

    const res = await apiFetch(`/api/equipos/${id}`, {
      method: 'DELETE',
    });

    if (res.success) {
      showToast(res.data?.message || 'Equipo removido con éxito.', 'success');
      loadData();
    } else {
      showToast(res.error || 'No se puede eliminar el equipo porque está asignado a un cliente activo.', 'error');
    }
  };

  const handleRegisterModelo = async (e: React.FormEvent) => {
    e.preventDefault();

    const cleanNom = nombreModelo.trim();
    if (!cleanNom || cleanNom.toLowerCase() === 'string') {
      showToast('El nombre del modelo de hardware es obligatorio.', 'error');
      return;
    }

    const payload: HardwareModelo = {
      idMarca: parseInt(idMarcaModelo),
      nombre: cleanNom,
      tipo: tipoTecnologicoModelo,
      descripcion: descripcionModelo.trim() || null,
    };

    const res = await apiFetch('/api/modelos', {
      method: 'POST',
      body: JSON.stringify(payload),
    });

    if (res.success) {
      showToast(res.data?.message || 'Modelo registrado con éxito.', 'success');
      setIdMarcaModelo('');
      setNombreModelo('');
      setDescripcionModelo('');
      loadData();
    } else {
      showToast(res.error || 'Fallo al guardar el nuevo modelo.', 'error');
    }
  };

  const handleDeleteModelo = async (id: number) => {
    if (!window.confirm(`¿Está seguro de eliminar este modelo de hardware (ID: ${id})?`)) {
      return;
    }

    const res = await apiFetch(`/api/modelos/${id}`, {
      method: 'DELETE',
    });

    if (res.success) {
      showToast(res.data?.message || 'Modelo eliminado del catálogo.', 'success');
      loadData();
    } else {
      showToast(res.error || 'Imposible eliminar. Hay equipos físicos en stock que son de este modelo.', 'error');
    }
  };

  const handleRegisterMarca = async (e: React.FormEvent) => {
    e.preventDefault();

    const cleanNom = nombreMarca.trim();
    if (!cleanNom || cleanNom.toLowerCase() === 'string') {
      showToast('El nombre de la marca es obligatorio.', 'error');
      return;
    }

    const res = await apiFetch('/api/modelos/marcas', {
      method: 'POST',
      body: JSON.stringify({ nombre: cleanNom }),
    });

    if (res.success) {
      showToast('Marca registrada con éxito.', 'success');
      setNombreMarca('');
      loadData();
    } else {
      showToast(res.error || 'Fallo al guardar la nueva marca.', 'error');
    }
  };

  const handleDeleteMarca = async (id: number) => {
    if (!window.confirm(`¿Está seguro de eliminar esta marca (ID: ${id})?`)) {
      return;
    }

    const res = await apiFetch(`/api/modelos/marcas/${id}`, {
      method: 'DELETE',
    });

    if (res.success) {
      showToast('Marca eliminada con éxito.', 'success');
      loadData();
    } else {
      showToast(res.error || 'No se puede eliminar la marca porque tiene modelos vinculados.', 'error');
    }
  };

  return (
    <div>
      {/* Sistema de Sub-pestañas Internas (Vercel-style) */}
      <div className="sub-tabs-container">
        <button 
          type="button"
          onClick={() => setActiveSubTab('stock')} 
          className={`sub-tab-btn ${activeSubTab === 'stock' ? 'active' : ''}`}
        >
          Control de Inventario y Stock
        </button>
        <button 
          type="button"
          onClick={() => setActiveSubTab('catalogo')} 
          className={`sub-tab-btn ${activeSubTab === 'catalogo' ? 'active' : ''}`}
        >
          Catálogo de Hardware (Modelos/Marcas)
        </button>
      </div>

      {activeSubTab === 'stock' && (
        <div className="animate-slide-up" style={{ display: 'flex', flexDirection: 'column', gap: '24px', marginBottom: '24px' }}>
          
          {/* 1. REGISTRO EQUIPO FISICO */}
          <div className="panel" style={{ marginBottom: 0 }}>
            <div className="panel-header">
              <div className="panel-title">
                {editingEquipoId ? <Edit size={16} /> : <Plus size={16} />} {editingEquipoId ? "Modificar Datos de Equipo en Stock" : "Ingreso de Equipos al Inventario (Stock)"}
              </div>
            </div>
            <form onSubmit={handleRegisterEquipo}>
              <div className="form-grid">
                <div className="form-group">
                  <label htmlFor="eq-modelo">Modelo de Equipo *</label>
                  <select 
                    id="eq-modelo" 
                    value={idModelo} 
                    onChange={(e) => setIdModelo(e.target.value)} 
                    required
                  >
                    <option value="">-- Seleccionar Modelo --</option>
                    {modelos.map(m => (
                      <option key={m.id} value={m.id}>
                        {m.marca} - {m.nombre} ({m.tipo})
                      </option>
                    ))}
                  </select>
                </div>
                <div className="form-group">
                  <label htmlFor="eq-mac">Dirección MAC Física *</label>
                  <input 
                    type="text" 
                    id="eq-mac" 
                    placeholder="Ej: AA:BB:CC:11:22:33 o aabbcc112233" 
                    value={mac}
                    onChange={(e) => setMac(e.target.value)}
                    required 
                  />
                </div>
                <div className="form-group">
                  <label htmlFor="eq-sn">Número de Serie (S/N)</label>
                  <input 
                    type="text" 
                    id="eq-sn" 
                    placeholder="Ej: SA12345678" 
                    value={numeroSerie}
                    onChange={(e) => setNumeroSerie(e.target.value)}
                  />
                </div>
                <div className="form-group">
                  <label htmlFor="eq-estado">Estado de Inventario *</label>
                  <select 
                    id="eq-estado" 
                    value={estado} 
                    onChange={(e) => setEstado(e.target.value)} 
                    required
                  >
                    <option value="INVENTARIO">INVENTARIO (Disponible en Stock)</option>
                    <option value="ACTIVO">ACTIVO (Instalado en Cliente)</option>
                    <option value="SUSPENDIDO">SUSPENDIDO (Retenido/Bloqueado)</option>
                    <option value="BAJA">BAJA (Fuera de Servicio/De Baja)</option>
                    <option value="FALLADO">FALLADO (Averiado/Para Reparar)</option>
                  </select>
                </div>
              </div>
              {editingEquipoId ? (
                <div style={{ display: 'flex', gap: '8px', marginTop: '16px' }}>
                  <button type="submit" className="btn btn-primary">
                    Guardar Cambios
                  </button>
                  <button type="button" className="btn" onClick={handleCancelEditEquipo}>
                    Cancelar
                  </button>
                </div>
              ) : (
                <button type="submit" className="btn btn-primary" style={{ marginTop: '16px' }}>
                  Registrar en Stock
                </button>
              )}
            </form>
          </div>

          {/* 2. TABLA INVENTARIO FISICO */}
          <div className="panel" style={{ marginBottom: 0 }}>
            <div className="panel-header">
              <div className="panel-title">
                <Cpu size={16} /> Inventario Físico de Equipos
              </div>
            </div>

            {/* BUSCADOR DE EQUIPOS EN INVENTARIO */}
            <div className="search-box" style={{ marginBottom: '16px', maxWidth: '400px' }}>
              <Search size={16} />
              <input 
                type="text" 
                placeholder="Buscar por MAC, Serie, Modelo o Estado..." 
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>

            <div className="table-responsive">
              <table>
                <thead>
                  <tr>
                    <th style={{ width: '80px' }}>ID</th>
                    <th>Modelo</th>
                    <th>Tecnología</th>
                    <th>MAC física</th>
                    <th>Nro. Serie</th>
                    <th>Estado de Stock</th>
                    <th>Fecha Registro</th>
                    <th style={{ width: '180px', textAlign: 'center' }}>Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr>
                      <td colSpan={8} style={{ textAlign: 'center', padding: '32px' }}>Cargando inventario...</td>
                    </tr>
                  ) : filteredEquipos.length === 0 ? (
                    <tr>
                      <td colSpan={8} style={{ textAlign: 'center', opacity: 0.5, padding: '32px' }}>No se encontraron equipos en stock.</td>
                    </tr>
                  ) : (
                    paginatedEquipos.map(e => (
                      <tr key={e.id}>
                        <td><strong>{e.id}</strong></td>
                        <td>{e.modelo}</td>
                        <td><span className="badge badge-stock" style={{ borderRadius: '0px' }}>{e.tipoTecnologico}</span></td>
                        <td><code>{e.mac}</code></td>
                        <td>{e.numeroSerie || '-'}</td>
                        <td>
                          <span className={`badge ${
                            e.estado === 'INVENTARIO' ? 'badge-stock' :
                            e.estado === 'ACTIVO' ? 'badge-active' :
                            e.estado === 'SUSPENDIDO' ? 'badge-suspended' :
                            e.estado === 'FALLADO' ? 'badge-danger' :
                            'badge-neutral'
                          }`}>
                            {e.estado}
                          </span>
                        </td>
                        <td>{e.fechaAlta ? new Date(e.fechaAlta).toLocaleDateString() : '-'}</td>
                        <td style={{ textAlign: 'center' }}>
                          <div style={{ display: 'flex', gap: '6px', justifyContent: 'center' }}>
                            <button 
                              onClick={() => handleEditEquipoClick(e)} 
                              className="btn btn-warning" 
                              style={{ padding: '6px 12px', display: 'inline-flex', gap: '4px', alignItems: 'center', fontSize: '11px' }}
                            >
                              <Edit size={12} />
                              Editar
                            </button>
                            <button 
                              onClick={() => handleDeleteEquipo(e.id!)} 
                              className="btn btn-danger" 
                              style={{ padding: '6px 12px', display: 'inline-flex', gap: '4px', alignItems: 'center', fontSize: '11px' }}
                            >
                              <Trash2 size={12} />
                              Borrar
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>

            {/* PAGINACIÓN DE EQUIPOS EN STOCK */}
            {totalItems > 0 && (
              <div style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                marginTop: '20px',
                paddingTop: '20px',
                borderTop: '1px solid var(--border-color)',
                flexWrap: 'wrap',
                gap: '12px'
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px', fontSize: '13px', color: 'var(--text-muted)' }}>
                  <span>
                    Mostrando <strong>{(currentPage - 1) * itemsPerPage + 1}</strong> a{' '}
                    <strong>{Math.min(currentPage * itemsPerPage, totalItems)}</strong> de{' '}
                    <strong>{totalItems}</strong> equipos
                  </span>
                  <select
                    value={itemsPerPage}
                    onChange={(e) => setItemsPerPage(parseInt(e.target.value))}
                    className="premium-select"
                    style={{ padding: '4px 8px', fontSize: '12px' }}
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

        </div>
      )}

      {activeSubTab === 'catalogo' && (
        <div className="animate-slide-up" style={{ display: 'grid', gridTemplateColumns: '1.2fr 1.2fr 1.6fr', gap: '24px', marginBottom: '24px' }}>
          
          {/* GESTIÓN DE MARCAS */}
          <div className="panel" style={{ marginBottom: '0', display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <div className="panel-header">
              <div className="panel-title">Marcas de Fabricantes</div>
            </div>
            <form onSubmit={handleRegisterMarca}>
              <div className="form-group" style={{ marginBottom: '12px' }}>
                <label htmlFor="ma-nom">Nueva Marca *</label>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <input 
                    type="text" 
                    id="ma-nom" 
                    placeholder="Ej: Cisco, Sagemcom" 
                    value={nombreMarca}
                    onChange={(e) => setNombreMarca(e.target.value)}
                    required 
                    style={{ flex: 1 }}
                  />
                  <button type="submit" className="btn btn-primary" style={{ padding: '0 12px', display: 'inline-flex', alignItems: 'center' }}>
                    <Plus size={16} />
                  </button>
                </div>
              </div>
            </form>
            <div style={{ flex: 1, border: '1px solid var(--border-color)', borderRadius: '4px', background: 'rgba(0,0,0,0.1)', overflowY: 'auto', maxHeight: '310px' }}>
              {marcas.length === 0 ? (
                <p style={{ textAlign: 'center', padding: '16px', opacity: 0.5, fontSize: '12px' }}>No hay marcas registradas.</p>
              ) : (
                marcas.map(m => (
                  <div key={m.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '8px 12px', borderBottom: '1px solid rgba(255,255,255,0.03)' }}>
                    <span style={{ fontSize: '12px', fontWeight: 'bold' }}>{m.nombre}</span>
                    <button 
                      onClick={() => handleDeleteMarca(m.id!)} 
                      style={{ background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer', fontSize: '11px' }}
                      title="Eliminar Marca"
                    >
                      🗑️
                    </button>
                  </div>
                ))
              )}
            </div>
          </div>

          {/* GESTIÓN DE MODELOS */}
          <div className="panel" style={{ marginBottom: '0' }}>
            <div className="panel-header">
              <div className="panel-title">Registrar Nuevo Modelo</div>
            </div>
            <form onSubmit={handleRegisterModelo}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                <div className="form-group">
                  <label htmlFor="m-marca">Marca de Fabricante *</label>
                  <select 
                    id="m-marca" 
                    value={idMarcaModelo} 
                    onChange={(e) => setIdMarcaModelo(e.target.value)} 
                    required
                  >
                    <option value="">-- Seleccionar Marca --</option>
                    {marcas.map(m => (
                      <option key={m.id} value={m.id}>{m.nombre}</option>
                    ))}
                  </select>
                </div>
                <div className="form-group">
                  <label htmlFor="m-nom">Nombre del Modelo *</label>
                  <input 
                    type="text" 
                    id="m-nom" 
                    placeholder="Ej: F@ST 3890" 
                    value={nombreModelo}
                    onChange={(e) => setNombreModelo(e.target.value)}
                    required 
                  />
                </div>
                <div className="form-group">
                  <label htmlFor="m-tipo">Tecnología de Red *</label>
                  <select 
                    id="m-tipo" 
                    value={tipoTecnologicoModelo} 
                    onChange={(e) => setTipoTecnologicoModelo(e.target.value as any)} 
                    required
                  >
                    <option value="DOCSIS">HFC (Cablemódem DOCSIS)</option>
                    <option value="GPON">FTTH (GPON ONT)</option>
                  </select>
                </div>
                <div className="form-group">
                  <label htmlFor="m-desc">Descripción Breve</label>
                  <input 
                    type="text" 
                    id="m-desc" 
                    placeholder="Ej: Wi-Fi 6, Dual-Band" 
                    value={descripcionModelo}
                    onChange={(e) => setDescripcionModelo(e.target.value)}
                  />
                </div>
              </div>
              <button type="submit" className="btn btn-primary" style={{ marginTop: '20px' }}>
                Crear Modelo
              </button>
            </form>
          </div>

          {/* LISTADO DE MODELOS */}
          <div className="panel" style={{ marginBottom: '0' }}>
            <div className="panel-header">
              <div className="panel-title">Modelos Registrados</div>
            </div>
            <div className="table-responsive" style={{ maxHeight: '310px', overflowY: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Marca</th>
                    <th>Modelo</th>
                    <th>Tecnología</th>
                    <th style={{ width: '80px', textAlign: 'center' }}>Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr>
                      <td colSpan={5} style={{ textAlign: 'center' }}>Cargando modelos...</td>
                    </tr>
                  ) : modelos.length === 0 ? (
                    <tr>
                      <td colSpan={5} style={{ textAlign: 'center', opacity: 0.5 }}>No hay modelos registrados.</td>
                    </tr>
                  ) : (
                    modelos.map(m => (
                      <tr key={m.id}>
                        <td><strong>{m.id}</strong></td>
                        <td>{m.marca}</td>
                        <td>{m.nombre}</td>
                        <td>
                          <span className="badge badge-stock" style={{ borderRadius: '0px' }}>
                            {m.tipo}
                          </span>
                        </td>
                        <td style={{ textAlign: 'center' }}>
                          <button 
                            onClick={() => handleDeleteModelo(m.id!)} 
                            className="btn btn-danger" 
                            style={{ padding: '4px 8px', fontSize: '10px' }}
                          >
                            Eliminar
                          </button>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>

        </div>
      )}
    </div>
  );
};

export default EquiposView;
