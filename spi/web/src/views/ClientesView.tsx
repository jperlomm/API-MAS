import React, { useState, useEffect } from 'react';
import { Plus, Search, Trash2, Edit, History } from 'lucide-react';
import { apiFetch } from '../utils/api';
import { Cliente, Localidad, Pais, Provincia } from '../utils/api';

interface ClientesViewProps {
  showToast: (message: string, type?: 'success' | 'error' | 'info') => void;
}

export const ClientesView: React.FC<ClientesViewProps> = ({ showToast }) => {
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [search, setSearch] = useState<string>('');
  
  // Pagination states
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [itemsPerPage, setItemsPerPage] = useState<number>(10);

  // Reset page when search term changes
  useEffect(() => {
    setCurrentPage(1);
  }, [search, itemsPerPage]);

  // Form states
  const [razonSocial, setRazonSocial] = useState<string>('');
  const [cuitDni, setCuitDni] = useState<string>('');
  const [telefono, setTelefono] = useState<string>('');
  const [email, setEmail] = useState<string>('');
  const [codigo, setCodigo] = useState<string>('');
  
  // Direccion Estructurada Selection States
  const [calle, setCalle] = useState<string>('');
  const [altura, setAltura] = useState<string>('');
  const [selectedCountryId, setSelectedCountryId] = useState<string>('');
  const [selectedProvinceId, setSelectedProvinceId] = useState<string>('');
  const [idLocalidad, setIdLocalidad] = useState<string>('');
  const [latitud, setLatitud] = useState<string>('');
  const [longitud, setLongitud] = useState<string>('');

  // Edit states
  const [editingClienteId, setEditingClienteId] = useState<number | null>(null);

  // Geographic master trees
  const [paises, setPaises] = useState<Pais[]>([]);
  const [provincias, setProvincias] = useState<Provincia[]>([]);
  const [localidades, setLocalidades] = useState<Localidad[]>([]);

  // Geographical Panel CRUD Tab states
  const [geoTab, setGeoTab] = useState<'paises' | 'provincias' | 'localidades'>('localidades');

  // Sub-tab de navegación interna
  const [activeSubTab, setActiveSubTab] = useState<'abonados' | 'geografia' | 'auditoria'>('abonados');

  // Audit Logs states
  const [auditLogs, setAuditLogs] = useState<any[]>([]);
  const [auditSearch, setAuditSearch] = useState<string>('');
  const [loadingLogs, setLoadingLogs] = useState<boolean>(false);

  const fetchAuditLogs = async (queryTerm = '', clientId?: number) => {
    setLoadingLogs(true);
    try {
      let url = '/api/clientes/logs';
      const params: string[] = [];
      if (clientId) params.push(`idCliente=${clientId}`);
      if (queryTerm.trim()) params.push(`query=${encodeURIComponent(queryTerm.trim())}`);
      if (params.length) url += '?' + params.join('&');

      const res = await apiFetch<any[]>(url);
      if (res.success && res.data) {
        setAuditLogs(res.data);
      } else {
        showToast('Error al cargar logs de auditoría.', 'error');
      }
    } catch (err: any) {
      showToast('Error de conexión al cargar logs.', 'error');
    } finally {
      setLoadingLogs(false);
    }
  };

  useEffect(() => {
    if (activeSubTab === 'auditoria') {
      fetchAuditLogs(auditSearch);
    }
  }, [activeSubTab]);

  // PAISES CRUD states
  const [editingPaisId, setEditingPaisId] = useState<number | null>(null);
  const [paisInput, setPaisInput] = useState<string>('');

  // PROVINCIAS CRUD states
  const [editingProvinciaId, setEditingProvinciaId] = useState<number | null>(null);
  const [provinciaInput, setProvinciaInput] = useState<string>('');
  const [provinciaPaisId, setProvinciaPaisId] = useState<string>('');

  // LOCALIDADES CRUD states
  const [editingLocalidadId, setEditingLocalidadId] = useState<number | null>(null);
  const [localidadInput, setLocalidadNombre] = useState<string>('');
  const [localidadProvinciaId, setLocalidadProvinciaId] = useState<string>('');

  const fetchClientes = async () => {
    setLoading(true);
    const res = await apiFetch<Cliente[]>('/api/clientes');
    if (res.success && res.data) {
      setClientes(res.data);
    } else {
      showToast(res.error || 'No se pudieron recuperar los abonados.', 'error');
    }
    setLoading(false);
  };

  const fetchPaises = async () => {
    const res = await apiFetch<Pais[]>('/api/paises');
    if (res.success && res.data) {
      setPaises(res.data);
    }
  };

  const fetchProvincias = async () => {
    const res = await apiFetch<Provincia[]>('/api/provincias');
    if (res.success && res.data) {
      setProvincias(res.data);
    }
  };

  const fetchLocalidades = async () => {
    const res = await apiFetch<Localidad[]>('/api/localidades');
    if (res.success && res.data) {
      setLocalidades(res.data);
    }
  };

  useEffect(() => {
    fetchClientes();
    fetchPaises();
    fetchProvincias();
    fetchLocalidades();
  }, []);

  // PAISES CRUD methods
  const handleAddOrUpdatePais = async (e: React.FormEvent) => {
    e.preventDefault();
    const name = paisInput.trim();
    if (!name) {
      showToast('El nombre del país es obligatorio.', 'error');
      return;
    }

    if (editingPaisId) {
      const res = await apiFetch<Pais>(`/api/paises/${editingPaisId}`, {
        method: 'PUT',
        body: JSON.stringify({ nombre: name }),
      });
      if (res.success) {
        showToast('País actualizado.', 'success');
        setEditingPaisId(null);
        setPaisInput('');
        fetchPaises();
      } else {
        showToast(res.error || 'Error al actualizar país.', 'error');
      }
    } else {
      const res = await apiFetch<Pais>('/api/paises', {
        method: 'POST',
        body: JSON.stringify({ nombre: name }),
      });
      if (res.success) {
        showToast('País registrado.', 'success');
        setPaisInput('');
        fetchPaises();
      } else {
        showToast(res.error || 'Error al registrar país.', 'error');
      }
    }
  };

  const handleEditPaisClick = (p: Pais) => {
    setEditingPaisId(p.id!);
    setPaisInput(p.nombre);
  };

  const handleCancelEditPais = () => {
    setEditingPaisId(null);
    setPaisInput('');
  };

  const handleDeletePais = async (id: number) => {
    if (!window.confirm('¿Está seguro que desea eliminar este país? Se eliminarán todas las provincias y localidades asociadas de forma automática.')) {
      return;
    }
    const res = await apiFetch(`/api/paises/${id}`, {
      method: 'DELETE',
    });
    if (res.success) {
      showToast('País eliminado con éxito.', 'success');
      if (editingPaisId === id) {
        setEditingPaisId(null);
        setPaisInput('');
      }
      fetchPaises();
      fetchProvincias();
      fetchLocalidades();
    } else {
      showToast(res.error || 'No se pudo eliminar el país.', 'error');
    }
  };

  // PROVINCIAS CRUD methods
  const handleAddOrUpdateProvincia = async (e: React.FormEvent) => {
    e.preventDefault();
    const name = provinciaInput.trim();
    const paisId = parseInt(provinciaPaisId);
    if (!name) {
      showToast('El nombre de la provincia es obligatorio.', 'error');
      return;
    }
    if (!paisId) {
      showToast('Debe asociar un país.', 'error');
      return;
    }

    if (editingProvinciaId) {
      const res = await apiFetch<Provincia>(`/api/provincias/${editingProvinciaId}`, {
        method: 'PUT',
        body: JSON.stringify({ nombre: name, idPais: paisId }),
      });
      if (res.success) {
        showToast('Provincia actualizada.', 'success');
        setEditingProvinciaId(null);
        setProvinciaInput('');
        setProvinciaPaisId('');
        fetchProvincias();
      } else {
        showToast(res.error || 'Error al actualizar provincia.', 'error');
      }
    } else {
      const res = await apiFetch<Provincia>('/api/provincias', {
        method: 'POST',
        body: JSON.stringify({ nombre: name, idPais: paisId }),
      });
      if (res.success) {
        showToast('Provincia registrada.', 'success');
        setProvinciaInput('');
        setProvinciaPaisId('');
        fetchProvincias();
      } else {
        showToast(res.error || 'Error al registrar provincia.', 'error');
      }
    }
  };

  const handleEditProvinciaClick = (prov: Provincia) => {
    setEditingProvinciaId(prov.id!);
    setProvinciaInput(prov.nombre);
    setProvinciaPaisId(String(prov.idPais));
  };

  const handleCancelEditProvincia = () => {
    setEditingProvinciaId(null);
    setProvinciaInput('');
    setProvinciaPaisId('');
  };

  const handleDeleteProvincia = async (id: number) => {
    if (!window.confirm('¿Está seguro que desea eliminar esta provincia? Se eliminarán todas las localidades y vínculos asociados de forma automática.')) {
      return;
    }
    const res = await apiFetch(`/api/provincias/${id}`, {
      method: 'DELETE',
    });
    if (res.success) {
      showToast('Provincia eliminada.', 'success');
      if (editingProvinciaId === id) {
        setEditingProvinciaId(null);
        setProvinciaInput('');
        setProvinciaPaisId('');
      }
      fetchProvincias();
      fetchLocalidades();
    } else {
      showToast(res.error || 'No se pudo eliminar la provincia.', 'error');
    }
  };

  // LOCALIDADES CRUD methods
  const handleAddOrUpdateLocalidad = async (e: React.FormEvent) => {
    e.preventDefault();
    const name = localidadInput.trim();
    const provId = parseInt(localidadProvinciaId);
    if (!name) {
      showToast('El nombre de la localidad es obligatorio.', 'error');
      return;
    }
    if (!provId) {
      showToast('Debe asociar una provincia.', 'error');
      return;
    }

    if (editingLocalidadId) {
      const res = await apiFetch<Localidad>(`/api/localidades/${editingLocalidadId}`, {
        method: 'PUT',
        body: JSON.stringify({ nombre: name, idProvincia: provId }),
      });
      if (res.success) {
        showToast('Localidad actualizada.', 'success');
        setEditingLocalidadId(null);
        setLocalidadNombre('');
        setLocalidadProvinciaId('');
        fetchLocalidades();
      } else {
        showToast(res.error || 'Error al actualizar localidad.', 'error');
      }
    } else {
      const res = await apiFetch<Localidad>('/api/localidades', {
        method: 'POST',
        body: JSON.stringify({ nombre: name, idProvincia: provId }),
      });
      if (res.success) {
        showToast('Localidad registrada con éxito.', 'success');
        setLocalidadNombre('');
        setLocalidadProvinciaId('');
        fetchLocalidades();
      } else {
        showToast(res.error || 'Error al registrar localidad.', 'error');
      }
    }
  };

  const handleEditLocalidadClick = (loc: Localidad) => {
    setEditingLocalidadId(loc.id!);
    setLocalidadNombre(loc.nombre);
    setLocalidadProvinciaId(String(loc.idProvincia));
  };

  const handleCancelEditLocalidad = () => {
    setEditingLocalidadId(null);
    setLocalidadNombre('');
    setLocalidadProvinciaId('');
  };

  const handleDeleteLocalidad = async (id: number) => {
    if (!window.confirm('¿Está seguro que desea eliminar esta localidad? Esta acción afectará a todos los abonados relacionados.')) {
      return;
    }
    const res = await apiFetch(`/api/localidades/${id}`, {
      method: 'DELETE',
    });
    if (res.success) {
      showToast('Localidad eliminada.', 'success');
      if (editingLocalidadId === id) {
        setEditingLocalidadId(null);
        setLocalidadNombre('');
        setLocalidadProvinciaId('');
      }
      fetchLocalidades();
    } else {
      showToast(res.error || 'No se puede eliminar la localidad porque posee abonados vinculados.', 'error');
    }
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();

    const cleanRazon = razonSocial.trim();
    const cleanCuitDni = cuitDni.trim().replace(/\./g, '');
    const cleanCodigo = codigo.trim();

    if (!cleanRazon || cleanRazon.toLowerCase() === 'string' || cleanRazon.toLowerCase() === 'test') {
      showToast('La Razón Social es obligatoria y no puede ser un texto genérico de prueba.', 'error');
      return;
    }
    if (cleanRazon.length < 3) {
      showToast('La Razón Social debe tener al menos 3 caracteres.', 'error');
      return;
    }

    if (!cleanCuitDni || cleanCuitDni.toLowerCase() === 'string') {
      showToast('El CUIT/DNI no puede estar vacío ni ser genérico.', 'error');
      return;
    }

    const cuitDniRegex = /^(\d{7,8}|\d{11}|\d{2}-\d{8}-\d{1})$/;
    if (!cuitDniRegex.test(cleanCuitDni)) {
      showToast('CUIT/DNI incorrecto. Use 7 u 8 dígitos para DNI, u 11 dígitos para CUIT.', 'error');
      return;
    }

    if (!cleanCodigo) {
      showToast('El Código de Abonado / Facturación es obligatorio.', 'error');
      return;
    }

    if (email) {
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(email.trim())) {
        showToast('El Correo Electrónico ingresado no tiene un formato válido.', 'error');
        return;
      }
    }

    if (telefono) {
      const phoneRegex = /^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s./0-9]{5,20}$/;
      if (!phoneRegex.test(telefono.trim())) {
        showToast('El formato del Teléfono no es válido.', 'error');
        return;
      }
    }

    if (!idLocalidad) {
      showToast('Debe seleccionar una localidad para la dirección estructurada.', 'error');
      return;
    }

    const payload: Cliente = {
      razonSocial: cleanRazon,
      cuitDni: cleanCuitDni,
      telefono: telefono.trim() || null,
      email: email.trim() || null,
      calle: calle.trim() || null,
      altura: altura.trim() || null,
      idLocalidad: parseInt(idLocalidad),
      codigo: cleanCodigo,
      latitud: latitud.trim() ? parseFloat(latitud) : null,
      longitud: longitud.trim() ? parseFloat(longitud) : null,
    };

    if (editingClienteId) {
      const res = await apiFetch(`/api/clientes/${editingClienteId}`, {
        method: 'PUT',
        body: JSON.stringify(payload),
      });

      if (res.success) {
        showToast(res.data?.message || 'Abonado comercial actualizado con éxito.', 'success');
        handleCancelEdit();
        fetchClientes();
      } else {
        showToast(res.error || 'Error al actualizar el abonado.', 'error');
      }
    } else {
      const res = await apiFetch('/api/clientes', {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      if (res.success) {
        showToast(res.data?.message || 'Cliente registrado con éxito.', 'success');
        setRazonSocial('');
        setCuitDni('');
        setTelefono('');
        setEmail('');
        setCodigo('');
        setCalle('');
        setAltura('');
        setSelectedCountryId('');
        setSelectedProvinceId('');
        setIdLocalidad('');
        setLatitud('');
        setLongitud('');
        fetchClientes();
      } else {
        showToast(res.error || 'Error al guardar el cliente.', 'error');
      }
    }
  };

  const handleEditClick = (cli: Cliente) => {
    setEditingClienteId(cli.id!);
    setRazonSocial(cli.razonSocial);
    setCuitDni(cli.cuitDni);
    setTelefono(cli.telefono || '');
    setEmail(cli.email || '');
    setCodigo(cli.codigo || '');
    setCalle(cli.calle || '');
    setAltura(cli.altura || '');
    setLatitud(cli.latitud ? String(cli.latitud) : '');
    setLongitud(cli.longitud ? String(cli.longitud) : '');

    if (cli.idLocalidad) {
      const locIdStr = String(cli.idLocalidad);
      setIdLocalidad(locIdStr);

      const matchedLoc = localidades.find(l => l.id === cli.idLocalidad);
      if (matchedLoc) {
        const provIdStr = String(matchedLoc.idProvincia);
        setSelectedProvinceId(provIdStr);

        const matchedProv = provincias.find(p => p.id === matchedLoc.idProvincia);
        if (matchedProv) {
          setSelectedCountryId(String(matchedProv.idPais));
        }
      }
    } else {
      setIdLocalidad('');
      setSelectedProvinceId('');
      setSelectedCountryId('');
    }
  };

  const handleCancelEdit = () => {
    setEditingClienteId(null);
    setRazonSocial('');
    setCuitDni('');
    setTelefono('');
    setEmail('');
    setCodigo('');
    setCalle('');
    setAltura('');
    setSelectedCountryId('');
    setSelectedProvinceId('');
    setIdLocalidad('');
    setLatitud('');
    setLongitud('');
  };

  const handleDelete = async (id: number) => {
    if (!window.confirm(`¿Está seguro que desea eliminar este cliente (ID: ${id})? Esta acción es irreversible.`)) {
      return;
    }

    const res = await apiFetch(`/api/clientes/${id}`, {
      method: 'DELETE',
    });

    if (res.success) {
      showToast(res.data?.message || 'Cliente dado de baja del sistema.', 'success');
      fetchClientes();
    } else {
      showToast(res.error || 'No se puede eliminar el cliente porque posee suscripciones o servicios activos.', 'error');
    }
  };

  const filteredClientes = clientes.filter(c => 
    c.razonSocial.toLowerCase().includes(search.toLowerCase()) ||
    c.cuitDni.toLowerCase().includes(search.toLowerCase()) ||
    (c.codigo || '').toLowerCase().includes(search.toLowerCase()) ||
    (c.direccion || '').toLowerCase().includes(search.toLowerCase())
  );

  // Pagination calculations
  const totalItems = filteredClientes.length;
  const totalPages = Math.ceil(totalItems / itemsPerPage);
  const paginatedClientes = filteredClientes.slice(
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

  // Client-side geographic filters
  const filteredProvinciasForForm = provincias.filter(p => p.idPais === parseInt(selectedCountryId));
  const filteredLocalidadesForForm = localidades.filter(l => l.idProvincia === parseInt(selectedProvinceId));

  return (
    <div>
      {/* Sistema de Sub-pestañas Internas (Vercel-style) */}
      <div className="sub-tabs-container">
        <button 
          type="button"
          onClick={() => setActiveSubTab('abonados')} 
          className={`sub-tab-btn ${activeSubTab === 'abonados' ? 'active' : ''}`}
        >
          Padrón de Abonados
        </button>
        <button 
          type="button"
          onClick={() => setActiveSubTab('geografia')} 
          className={`sub-tab-btn ${activeSubTab === 'geografia' ? 'active' : ''}`}
        >
          Gestión Geográfica (Catálogos)
        </button>
        <button 
          type="button"
          onClick={() => setActiveSubTab('auditoria')} 
          className={`sub-tab-btn ${activeSubTab === 'auditoria' ? 'active' : ''}`}
        >
          🔍 Auditoría de Cambios
        </button>
      </div>

      {activeSubTab === 'abonados' && (
        <div className="animate-slide-up" style={{ display: 'flex', flexDirection: 'column', gap: '24px', marginBottom: '24px' }}>
          
          {/* PANEL REGISTRO DE ABONADO */}
          <div className="panel" style={{ marginBottom: 0 }}>
            <div className="panel-header">
              <div className="panel-title">
                {editingClienteId ? <Edit size={16} /> : <Plus size={16} />} {editingClienteId ? "Modificar Abonado Comercial" : "Registrar Nuevo Abonado"}
              </div>
            </div>
            <form onSubmit={handleRegister}>
              <div className="form-grid">
                <div className="form-group" style={{ gridColumn: 'span 2' }}>
                  <label htmlFor="c-razon">Nombre / Razón Social *</label>
                  <input 
                    type="text" 
                    id="c-razon" 
                    placeholder="Ej: Cooperativa Eléctrica"
                    value={razonSocial}
                    onChange={(e) => setRazonSocial(e.target.value)}
                    required
                  />
                </div>
                <div className="form-group">
                  <label htmlFor="c-doc">CUIT / DNI *</label>
                  <input 
                    type="text" 
                    id="c-doc" 
                    placeholder="Ej: 20-35888999-4 o 35888999"
                    value={cuitDni}
                    onChange={(e) => setCuitDni(e.target.value)}
                    required
                  />
                </div>
                <div className="form-group">
                  <label htmlFor="c-codigo">Código de Facturación *</label>
                  <input 
                    type="text" 
                    id="c-codigo" 
                    placeholder="Ej: AB-4921"
                    value={codigo}
                    onChange={(e) => setCodigo(e.target.value)}
                    required
                  />
                </div>
                <div className="form-group">
                  <label htmlFor="c-tel">Teléfono de Contacto</label>
                  <input 
                    type="text" 
                    id="c-tel" 
                    placeholder="Ej: 2615551234"
                    value={telefono}
                    onChange={(e) => setTelefono(e.target.value)}
                  />
                </div>
                <div className="form-group">
                  <label htmlFor="c-email">Correo Electrónico</label>
                  <input 
                    type="email" 
                    id="c-email" 
                    placeholder="Ej: contacto@isp.com"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                  />
                </div>

                {/* DIRECCIÓN ESTRUCTURADA */}
                <div className="form-group" style={{ gridColumn: 'span 2' }}>
                  <label htmlFor="c-calle">Calle *</label>
                  <input 
                    type="text" 
                    id="c-calle" 
                    placeholder="Ej: Av. San Martín"
                    value={calle}
                    onChange={(e) => setCalle(e.target.value)}
                    required
                  />
                </div>
                <div className="form-group">
                  <label htmlFor="c-altura">Altura / Número *</label>
                  <input 
                    type="text" 
                    id="c-altura" 
                    placeholder="Ej: 1045"
                    value={altura}
                    onChange={(e) => setAltura(e.target.value)}
                    required
                  />
                </div>

                {/* PAIS FORM DROPDOWN */}
                <div className="form-group">
                  <label htmlFor="c-pais-sel">País *</label>
                  <select 
                    id="c-pais-sel" 
                    value={selectedCountryId} 
                    onChange={(e) => {
                      setSelectedCountryId(e.target.value);
                      setSelectedProvinceId('');
                      setIdLocalidad('');
                    }}
                    required
                  >
                    <option value="">-- Seleccionar --</option>
                    {paises.map(p => (
                      <option key={p.id} value={p.id}>{p.nombre}</option>
                    ))}
                  </select>
                </div>

                {/* PROVINCIA FORM DROPDOWN */}
                <div className="form-group">
                  <label htmlFor="c-provincia-sel">Provincia / Estado *</label>
                  <select 
                    id="c-provincia-sel" 
                    value={selectedProvinceId} 
                    onChange={(e) => {
                      setSelectedProvinceId(e.target.value);
                      setIdLocalidad('');
                    }}
                    required
                  >
                    <option value="">-- Seleccionar --</option>
                    {filteredProvinciasForForm.map(p => (
                      <option key={p.id} value={p.id}>{p.nombre}</option>
                    ))}
                  </select>
                </div>

                {/* LOCALIDAD FORM DROPDOWN */}
                <div className="form-group">
                  <label htmlFor="c-localidad-sel">Ciudad / Localidad *</label>
                  <select 
                    id="c-localidad-sel" 
                    value={idLocalidad} 
                    onChange={(e) => setIdLocalidad(e.target.value)}
                    required
                  >
                    <option value="">-- Seleccionar --</option>
                    {filteredLocalidadesForForm.map(l => (
                      <option key={l.id} value={l.id}>{l.nombre}</option>
                    ))}
                  </select>
                </div>

                {/* COORDENADAS GEOGRÁFICAS (LAT/LNG) */}
                <div className="form-group">
                  <label htmlFor="c-lat">Latitud (Opcional)</label>
                  <input 
                    type="text" 
                    id="c-lat" 
                    placeholder="Ej: -34.6037"
                    value={latitud}
                    onChange={(e) => setLatitud(e.target.value)}
                  />
                </div>
                <div className="form-group">
                  <label htmlFor="c-lng">Longitud (Opcional)</label>
                  <input 
                    type="text" 
                    id="c-lng" 
                    placeholder="Ej: -58.3816"
                    value={longitud}
                    onChange={(e) => setLongitud(e.target.value)}
                  />
                </div>
              </div>
              {editingClienteId ? (
                <div style={{ display: 'flex', gap: '8px', marginTop: '16px' }}>
                  <button type="submit" className="btn btn-primary">
                    Guardar Cambios
                  </button>
                  <button type="button" className="btn" onClick={handleCancelEdit}>
                    Cancelar
                  </button>
                </div>
              ) : (
                <button type="submit" className="btn btn-primary" style={{ marginTop: '16px' }}>
                  Registrar Cliente
                </button>
              )}
            </form>
          </div>

        </div>
      )}

      {activeSubTab === 'geografia' && (
        <div className="animate-slide-up" style={{ maxWidth: '800px', margin: '0 auto 24px auto' }}>
          
          {/* PANEL CRUD GEOGRÁFICO DE PESTAÑAS */}
          <div className="panel" style={{ marginBottom: 0, display: 'flex', flexDirection: 'column' }}>
            <div className="panel-header">
              <div className="panel-title">Estructura Geográfica de Abonados</div>
            </div>
            
            {/* SUB-PESTAÑAS DE GEOGRAFÍA PREMIUM CONSISTENTES */}
            <div className="sub-tabs-container" style={{ marginBottom: '16px', gap: '8px' }}>
              <button 
                type="button" 
                onClick={() => { setGeoTab('paises'); }}
                className={`sub-tab-btn ${geoTab === 'paises' ? 'active' : ''}`}
                style={{ padding: '6px 12px', fontSize: '11px' }}
              >
                Países
              </button>
              <button 
                type="button" 
                onClick={() => { setGeoTab('provincias'); }}
                className={`sub-tab-btn ${geoTab === 'provincias' ? 'active' : ''}`}
                style={{ padding: '6px 12px', fontSize: '11px' }}
              >
                Provincias / Estados
              </button>
              <button 
                type="button" 
                onClick={() => { setGeoTab('localidades'); }}
                className={`sub-tab-btn ${geoTab === 'localidades' ? 'active' : ''}`}
                style={{ padding: '6px 12px', fontSize: '11px' }}
              >
                Ciudades / Localidades
              </button>
            </div>

            {/* TAB PAISES */}
            {geoTab === 'paises' && (
              <div>
                <form onSubmit={handleAddOrUpdatePais} style={{ marginBottom: '12px' }}>
                  <label style={{ fontSize: '10px', textTransform: 'uppercase', color: 'var(--text-muted)', marginBottom: '4px', display: 'block' }}>
                    {editingPaisId ? 'Editar País' : 'Nuevo País'}
                  </label>
                  <div style={{ display: 'flex', gap: '6px' }}>
                    <input 
                      type="text" 
                      placeholder="Nombre del País (ej: Argentina)" 
                      value={paisInput} 
                      onChange={(e) => setPaisInput(e.target.value)}
                      required
                      style={{ flex: 1, padding: '6px', fontSize: '12px' }}
                    />
                    {editingPaisId && (
                      <button type="button" onClick={handleCancelEditPais} className="btn btn-secondary" style={{ padding: '6px 10px', fontSize: '12px' }}>
                        Cancelar
                      </button>
                    )}
                    <button type="submit" className="btn btn-primary" style={{ padding: '6px 12px', fontSize: '12px' }}>
                      {editingPaisId ? 'Guardar' : 'Registrar'}
                    </button>
                  </div>
                </form>
                <div style={{ overflowY: 'auto', maxHeight: '200px', border: '1px solid var(--border-color)', borderRadius: '4px', background: 'rgba(0,0,0,0.1)' }}>
                  {paises.length === 0 ? (
                    <p style={{ textAlign: 'center', padding: '12px', opacity: 0.5, fontSize: '11px' }}>No hay países registrados.</p>
                  ) : (
                    paises.map(p => (
                      <div key={p.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '6px 10px', borderBottom: '1px solid rgba(255,255,255,0.03)' }}>
                        <span style={{ fontSize: '12px', fontWeight: 'bold' }}>{p.nombre}</span>
                        <div style={{ display: 'flex', gap: '4px' }}>
                          <button type="button" onClick={() => handleEditPaisClick(p)} style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '11px' }} title="Editar">✏️</button>
                          <button type="button" onClick={() => handleDeletePais(p.id!)} style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '11px' }} title="Eliminar">🗑️</button>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </div>
            )}

            {/* TAB PROVINCIAS */}
            {geoTab === 'provincias' && (
              <div>
                <form onSubmit={handleAddOrUpdateProvincia} style={{ marginBottom: '12px' }}>
                  <label style={{ fontSize: '10px', textTransform: 'uppercase', color: 'var(--text-muted)', marginBottom: '4px', display: 'block' }}>
                    {editingProvinciaId ? 'Editar Provincia' : 'Nueva Provincia'}
                  </label>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                    <input 
                      type="text" 
                      placeholder="Nombre (ej: Mendoza)" 
                      value={provinciaInput} 
                      onChange={(e) => setProvinciaInput(e.target.value)}
                      required
                      style={{ padding: '6px', fontSize: '12px' }}
                    />
                    <select 
                      value={provinciaPaisId}
                      onChange={(e) => setProvinciaPaisId(e.target.value)}
                      required
                      style={{ padding: '6px', fontSize: '12px' }}
                    >
                      <option value="">-- Seleccionar País Padre --</option>
                      {paises.map(p => (
                        <option key={p.id} value={p.id}>{p.nombre}</option>
                      ))}
                    </select>
                    <div style={{ display: 'flex', gap: '6px', justifyContent: 'flex-end' }}>
                      {editingProvinciaId && (
                        <button type="button" onClick={handleCancelEditProvincia} className="btn btn-secondary" style={{ padding: '6px 10px', fontSize: '12px' }}>
                          Cancelar
                        </button>
                      )}
                      <button type="submit" className="btn btn-primary" style={{ padding: '6px 12px', fontSize: '12px' }}>
                        {editingProvinciaId ? 'Guardar Cambios' : 'Registrar Provincia'}
                      </button>
                    </div>
                  </div>
                </form>
                <div style={{ overflowY: 'auto', maxHeight: '200px', border: '1px solid var(--border-color)', borderRadius: '4px', background: 'rgba(0,0,0,0.1)' }}>
                  {provincias.length === 0 ? (
                    <p style={{ textAlign: 'center', padding: '12px', opacity: 0.5, fontSize: '11px' }}>No hay provincias registradas.</p>
                  ) : (
                    provincias.map(pr => (
                      <div key={pr.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '6px 10px', borderBottom: '1px solid rgba(255,255,255,0.03)' }}>
                        <div>
                          <span style={{ fontSize: '12px', fontWeight: 'bold' }}>{pr.nombre}</span>
                          <span style={{ fontSize: '10px', opacity: 0.5, marginLeft: '6px' }}>({pr.pais})</span>
                        </div>
                        <div style={{ display: 'flex', gap: '4px' }}>
                          <button type="button" onClick={() => handleEditProvinciaClick(pr)} style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '11px' }} title="Editar">✏️</button>
                          <button type="button" onClick={() => handleDeleteProvincia(pr.id!)} style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '11px' }} title="Eliminar">🗑️</button>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </div>
            )}

            {/* TAB LOCALIDADES */}
            {geoTab === 'localidades' && (
              <div>
                <form onSubmit={handleAddOrUpdateLocalidad} style={{ marginBottom: '12px' }}>
                  <label style={{ fontSize: '10px', textTransform: 'uppercase', color: 'var(--text-muted)', marginBottom: '4px', display: 'block' }}>
                    {editingLocalidadId ? 'Editar Localidad' : 'Nueva Localidad'}
                  </label>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                    <input 
                      type="text" 
                      placeholder="Nombre (ej: Luján de Cuyo)" 
                      value={localidadInput} 
                      onChange={(e) => setLocalidadNombre(e.target.value)}
                      required
                      style={{ padding: '6px', fontSize: '12px' }}
                    />
                    <select 
                      value={localidadProvinciaId}
                      onChange={(e) => setLocalidadProvinciaId(e.target.value)}
                      required
                      style={{ padding: '6px', fontSize: '12px' }}
                    >
                      <option value="">-- Seleccionar Provincia Padre --</option>
                      {provincias.map(pr => (
                        <option key={pr.id} value={pr.id}>{pr.nombre} ({pr.pais})</option>
                      ))}
                    </select>
                    <div style={{ display: 'flex', gap: '6px', justifyContent: 'flex-end' }}>
                      {editingLocalidadId && (
                        <button type="button" onClick={handleCancelEditLocalidad} className="btn btn-secondary" style={{ padding: '6px 10px', fontSize: '12px' }}>
                          Cancelar
                        </button>
                      )}
                      <button type="submit" className="btn btn-primary" style={{ padding: '6px 12px', fontSize: '12px' }}>
                        {editingLocalidadId ? 'Guardar Cambios' : 'Registrar Localidad'}
                      </button>
                    </div>
                  </div>
                </form>
                <div style={{ overflowY: 'auto', maxHeight: '200px', border: '1px solid var(--border-color)', borderRadius: '4px', background: 'rgba(0,0,0,0.1)' }}>
                  {localidades.length === 0 ? (
                    <p style={{ textAlign: 'center', padding: '12px', opacity: 0.5, fontSize: '11px' }}>No hay localidades registradas.</p>
                  ) : (
                    localidades.map(l => (
                      <div key={l.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '6px 10px', borderBottom: '1px solid rgba(255,255,255,0.03)' }}>
                        <div>
                          <span style={{ fontSize: '12px', fontWeight: 'bold' }}>{l.nombre}</span>
                          <span style={{ fontSize: '10px', opacity: 0.5, marginLeft: '6px' }}>({l.provincia})</span>
                        </div>
                        <div style={{ display: 'flex', gap: '4px' }}>
                          <button type="button" onClick={() => handleEditLocalidadClick(l)} style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '11px' }} title="Editar">✏️</button>
                          <button type="button" onClick={() => handleDeleteLocalidad(l.id!)} style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '11px' }} title="Eliminar">🗑️</button>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </div>
            )}

          </div>

        </div>
      )}

      {/* RENDERIZADO DEL LISTADO DE CLIENTES SOLO EN SUB-TAB DE ABONADOS */}
      {activeSubTab === 'abonados' && (
      <div className="panel">
        <div className="panel-header">
          <div className="panel-title">Listado de Abonados Registrados</div>
        </div>

        <div className="search-box" style={{ marginBottom: '16px', maxWidth: '400px' }}>
          <Search size={16} />
          <input 
            type="text" 
            placeholder="Buscar por Razón Social, CUIT/DNI o dirección..." 
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        <div className="table-responsive">
          <table>
            <thead>
              <tr>
                <th style={{ width: '80px' }}>ID</th>
                <th style={{ width: '120px' }}>Código</th>
                <th>Nombre / Razón Social</th>
                <th>CUIT/DNI</th>
                <th>Teléfono</th>
                <th>Email</th>
                <th>Dirección de Instalación</th>
                <th>Coordenadas</th>
                <th style={{ width: '180px', textAlign: 'center' }}>Acciones</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={9} style={{ textAlign: 'center', padding: '32px' }}>
                    Cargando abonados...
                  </td>
                </tr>
              ) : paginatedClientes.length === 0 ? (
                <tr>
                  <td colSpan={9} style={{ textAlign: 'center', opacity: 0.5, padding: '32px' }}>
                    No se encontraron clientes registrados.
                  </td>
                </tr>
              ) : (
                paginatedClientes.map((c) => (
                  <tr key={c.id}>
                    <td><strong>{c.id}</strong></td>
                    <td>
                      <span className="badge badge-stock" style={{ background: 'rgba(0,180,216,0.1)', color: '#00b4d8', border: '1px solid rgba(0,180,216,0.3)', fontWeight: 'bold' }}>
                        {c.codigo}
                      </span>
                    </td>
                    <td>{c.razonSocial}</td>
                    <td><code>{c.cuitDni}</code></td>
                    <td>{c.telefono || '-'}</td>
                    <td>{c.email || '-'}</td>
                    <td>{c.direccion || '-'}</td>
                    <td>
                      {c.latitud && c.longitud ? (
                        <a 
                          href={`https://www.google.com/maps/search/?api=1&query=${c.latitud},${c.longitud}`} 
                          target="_blank" 
                          rel="noopener noreferrer"
                          className="badge"
                          style={{ textDecoration: 'none', background: 'rgba(40,167,69,0.1)', color: '#28a745', border: '1px solid rgba(40,167,69,0.3)', display: 'inline-flex', alignItems: 'center', gap: '4px', fontSize: '11px', cursor: 'pointer' }}
                          title="Ver en Google Maps"
                        >
                          📍 {Number(c.latitud).toFixed(4)}, {Number(c.longitud).toFixed(4)}
                        </a>
                      ) : (
                        <span style={{ opacity: 0.4, fontSize: '11px' }}>-</span>
                      )}
                    </td>
                    <td style={{ textAlign: 'center' }}>
                      <div style={{ display: 'flex', gap: '6px', justifyContent: 'center' }}>
                        <button 
                          onClick={() => handleEditClick(c)} 
                          className="btn btn-warning" 
                          style={{ padding: '6px 12px', display: 'inline-flex', gap: '4px', alignItems: 'center', fontSize: '11px' }}
                          title="Editar Abonado"
                        >
                          <Edit size={12} />
                          Editar
                        </button>
                        <button 
                          onClick={() => handleDelete(c.id!)} 
                          className="btn btn-danger" 
                          style={{ padding: '6px 12px', display: 'inline-flex', gap: '4px', alignItems: 'center', fontSize: '11px' }}
                          title="Eliminar Abonado"
                        >
                          <Trash2 size={12} />
                          Baja
                        </button>
                      </div>
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
            borderTop: '1px solid var(--border-color)',
            flexWrap: 'wrap',
            gap: '12px'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', fontSize: '13px', color: 'var(--text-muted)' }}>
              <span>
                Mostrando <strong>{(currentPage - 1) * itemsPerPage + 1}</strong> a{' '}
                <strong>{Math.min(currentPage * itemsPerPage, totalItems)}</strong> de{' '}
                <strong>{totalItems}</strong> abonados
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
      )}

      {activeSubTab === 'auditoria' && (
        <div className="animate-slide-up" style={{ display: 'flex', flexDirection: 'column', gap: '20px', marginBottom: '24px' }}>
          
          {/* PANEL DE BÚSQUEDA Y FILTROS DE LOGS */}
          <div className="panel" style={{ padding: '20px', marginBottom: 0 }}>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '16px', alignItems: 'center', justifyContent: 'space-between' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 'bold', color: 'var(--text-color)' }}>
                  📋 Registro de Auditoría de Abonados
                </h3>
                <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-muted)' }}>
                  Monitoreo de movimientos de red, recambios de módem, cambios de dirección y estados de servicios.
                </p>
              </div>

              {/* Input de búsqueda premium */}
              <div style={{ display: 'flex', gap: '8px', minWidth: '320px', flex: '1 1 auto', justifyContent: 'flex-end' }}>
                <div style={{ position: 'relative', width: '100%', maxWidth: '360px' }}>
                  <span style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }}>
                    <Search size={14} />
                  </span>
                  <input
                    type="text"
                    placeholder="Buscar por cliente, operador, acción o detalle..."
                    value={auditSearch}
                    onChange={(e) => setAuditSearch(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        fetchAuditLogs(auditSearch);
                      }
                    }}
                    style={{
                      width: '100%',
                      padding: '8px 12px 8px 32px',
                      borderRadius: '4px',
                      border: '1px solid var(--border-color)',
                      background: 'rgba(255,255,255,0.03)',
                      color: 'var(--text-color)',
                      fontSize: '13px'
                    }}
                  />
                </div>
                <button
                  type="button"
                  onClick={() => fetchAuditLogs(auditSearch)}
                  className="btn btn-primary"
                  style={{ padding: '8px 16px', fontSize: '13px' }}
                >
                  Buscar
                </button>
              </div>
            </div>
          </div>

          {/* TABLA DE AUDITORÍA PREMIUM */}
          <div className="panel" style={{ marginBottom: 0 }}>
            {loadingLogs ? (
              <div style={{ padding: '40px', textAlign: 'center', color: 'var(--text-muted)' }}>
                <span className="spinner" style={{ display: 'inline-block', width: '20px', height: '20px', border: '2px solid var(--border-color)', borderTopColor: 'var(--accent)', borderRadius: '50%', animation: 'spin 1s linear infinite', marginRight: '8px', verticalAlign: 'middle' }}></span>
                Cargando logs de auditoría...
              </div>
            ) : auditLogs.length === 0 ? (
              <div style={{ padding: '60px 40px', textAlign: 'center', color: 'var(--text-muted)' }}>
                <History size={32} style={{ opacity: 0.3, marginBottom: '12px' }} />
                <p style={{ margin: 0, fontSize: '14px', fontWeight: '500' }}>No se encontraron registros de auditoría en la búsqueda actual.</p>
                <p style={{ margin: '4px 0 0 0', fontSize: '12px' }}>Intente con otro término o espere a que se generen transacciones.</p>
              </div>
            ) : (
              <div className="table-responsive" style={{ maxHeight: '600px', overflowY: 'auto' }}>
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: '150px' }}>Fecha y Hora</th>
                      <th style={{ width: '180px' }}>Abonado</th>
                      <th style={{ width: '130px' }}>Operador / Usuario</th>
                      <th style={{ width: '150px' }}>Acción</th>
                      <th>Detalle del Cambio</th>
                    </tr>
                  </thead>
                  <tbody>
                    {auditLogs.map((log) => {
                      // Color mapping for action badges
                      let badgeStyle: React.CSSProperties = {
                        display: 'inline-block',
                        padding: '2px 8px',
                        borderRadius: '12px',
                        fontSize: '11px',
                        fontWeight: '600',
                        textTransform: 'uppercase'
                      };

                      if (log.accion.includes('ALTA')) {
                        badgeStyle.backgroundColor = 'rgba(46, 204, 113, 0.15)';
                        badgeStyle.color = '#2ecc71';
                      } else if (log.accion.includes('BAJA')) {
                        badgeStyle.backgroundColor = 'rgba(231, 76, 60, 0.15)';
                        badgeStyle.color = '#e74c3c';
                      } else if (log.accion.includes('CAMBIO_EQUIPO') || log.accion.includes('EQUIPO')) {
                        badgeStyle.backgroundColor = 'rgba(155, 89, 182, 0.15)';
                        badgeStyle.color = '#9b59b6';
                      } else if (log.accion.includes('ESTADO')) {
                        badgeStyle.backgroundColor = 'rgba(241, 196, 15, 0.15)';
                        badgeStyle.color = '#f1c40f';
                      } else {
                        badgeStyle.backgroundColor = 'rgba(52, 152, 219, 0.15)';
                        badgeStyle.color = '#3498db';
                      }

                      return (
                        <tr key={log.id} style={{ transition: 'background 0.2s' }}>
                          <td style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                            {new Date(log.fecha).toLocaleString('es-AR', {
                              year: 'numeric',
                              month: '2-digit',
                              day: '2-digit',
                              hour: '2-digit',
                              minute: '2-digit',
                              second: '2-digit'
                            })}
                          </td>
                          <td style={{ fontWeight: '500' }}>
                            {log.nombreCliente || <span style={{ fontStyle: 'italic', color: 'var(--text-muted)' }}>No asignado</span>}
                          </td>
                          <td>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                              <span style={{
                                width: '16px',
                                height: '16px',
                                borderRadius: '50%',
                                backgroundColor: 'var(--accent)',
                                color: '#fff',
                                display: 'flex',
                                alignItems: 'center',
                                justifyContent: 'center',
                                fontSize: '9px',
                                fontWeight: 'bold'
                              }}>
                                {log.usuario.substring(0, 1).toUpperCase()}
                              </span>
                              <span style={{ fontSize: '13px' }}>{log.usuario}</span>
                            </div>
                          </td>
                          <td>
                            <span style={badgeStyle}>
                              {log.accion.replace('_CLIENTE', '').replace('_SERVICIO', '').replace('_', ' ')}
                            </span>
                          </td>
                          <td style={{ fontSize: '13px', lineHeight: '1.4', color: 'rgba(255,255,255,0.85)' }}>
                            {log.detalle}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
            
            {/* Pie de tabla informativo sobre retención */}
            <div style={{
              padding: '12px 20px',
              borderTop: '1px solid var(--border-color)',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              backgroundColor: 'rgba(255,255,255,0.01)'
            }}>
              <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                ℹ️ Los registros se rotan automáticamente para optimizar el rendimiento. Historial máximo guardado: <strong>180 días</strong>.
              </span>
              <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                Total mostrados: <strong>{auditLogs.length} registros</strong>
              </span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ClientesView;
