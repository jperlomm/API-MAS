import React, { useState, useEffect } from 'react';
import { Network, Plus, Trash2, Edit } from 'lucide-react';
import { apiFetch, CMTS, Subred, Pool, Paquete } from '../utils/api';

interface RedViewProps {
  showToast: (msg: string, type: 'success' | 'error') => void;
}

// IP Math Helpers for IPAM Auto-completion
function ipToNum(ip: string): number {
  const parts = ip.split('.').map(Number);
  if (parts.length !== 4 || parts.some(isNaN)) return 0;
  return parts[0] * 16777216 + parts[1] * 65536 + parts[2] * 256 + parts[3];
}

function numToIp(num: number): string {
  const a = Math.floor(num / 16777216) % 256;
  const b = Math.floor(num / 65536) % 256;
  const c = Math.floor(num / 256) % 256;
  const d = num % 256;
  return `${a}.${b}.${c}.${d}`;
}

function parseCidr(cidr: string) {
  const [ip, maskStr] = cidr.split('/');
  const mask = parseInt(maskStr, 10);
  const network = ipToNum(ip);
  const size = Math.pow(2, 32 - mask);
  
  let firstUsable = network + 1;
  let lastUsable = network + size - 2;
  if (size <= 2) {
    firstUsable = network;
    lastUsable = network + size - 1;
  }
  return { network, size, firstUsable, lastUsable };
}

function getAvailableGaps(firstUsable: number, lastUsable: number, occupied: { start: number, end: number }[]) {
  const sorted = [...occupied].sort((a, b) => a.start - b.start);
  const gaps: { start: number, end: number }[] = [];
  
  let currentStart = firstUsable;
  for (const interval of sorted) {
    if (interval.start > currentStart) {
      gaps.push({ start: currentStart, end: interval.start - 1 });
    }
    currentStart = Math.max(currentStart, interval.end + 1);
  }
  
  if (currentStart <= lastUsable) {
    gaps.push({ start: currentStart, end: lastUsable });
  }
  return gaps;
}

export const RedView: React.FC<RedViewProps> = ({ showToast }) => {
  const [cmtsList, setCmtsList] = useState<CMTS[]>([]);
  const [subredList, setSubredList] = useState<Subred[]>([]);
  const [poolList, setPoolList] = useState<Pool[]>([]);
  const [paqueteList, setPaqueteList] = useState<Paquete[]>([]);
  const [loading, setLoading] = useState<boolean>(true);

  // Forms states
  const [cmtsNombre, setCmtsNombre] = useState<string>('');
  const [cmtsIp, setCmtsIp] = useState<string>('');
  const [cmtsSnmp, setCmtsSnmp] = useState<string>('');

  const [subIdCmts, setSubIdCmts] = useState<string>('');
  const [subNombre, setSubNombre] = useState<string>('');
  const [subCidr, setSubCidr] = useState<string>('');
  const [subGw, setSubGateway] = useState<string>('');
  const [subTipo, setSubTipo] = useState<string>('CM');

  const [poolIdSubred, setPoolIdSubred] = useState<string>('');
  const [poolInicio, setPoolInicio] = useState<string>('');
  const [poolFin, setPoolFin] = useState<string>('');
  const [poolClientClass, setPoolClientClass] = useState<string>('');
  const [poolEsEstatico, setPoolEsEstatico] = useState<boolean>(false);
  const [isCreatingNewClass, setIsCreatingNewClass] = useState<boolean>(false);
  const [poolFormError, setPoolFormError] = useState<string | null>(null);

  const [paqNombre, setPaqNombre] = useState<string>('');
  const [paqDown, setPaqDown] = useState<string>('');
  const [paqUp, setPaqUp] = useState<string>('');
  const [paqLimit, setPaqLimit] = useState<string>('1');
  const [paqBootfile, setPaqBootfile] = useState<string>('');
  const [paqClientClass, setPaqClientClass] = useState<string>('');
  const [paqClassMode, setPaqClassMode] = useState<'auto' | 'select' | 'custom'>('auto');
  const [bootfilesList, setBootfilesList] = useState<{name: string, type: string}[]>([]);

  // Context Filter State
  const [selectedFilterCmtsId, setSelectedFilterCmtsId] = useState<number | 'ALL'>('ALL');

  // Sub-tabs navegación interna
  const [activeSubTab, setActiveSubTab] = useState<'cmts' | 'ipam' | 'planes'>('cmts');

  // Editing States
  const [editingCmtsId, setEditingCmtsId] = useState<number | null>(null);
  const [editingSubredId, setEditingSubredId] = useState<number | null>(null);
  const [editingPoolId, setEditingPoolId] = useState<number | null>(null);
  const [editingPaqueteId, setEditingPaqueteId] = useState<number | null>(null);

  // Auto-select CMTS when context filter is active
  useEffect(() => {
    if (selectedFilterCmtsId !== 'ALL' && !editingSubredId) {
      setSubIdCmts(String(selectedFilterCmtsId));
    } else if (selectedFilterCmtsId === 'ALL' && !editingSubredId) {
      setSubIdCmts('');
    }
  }, [selectedFilterCmtsId, editingSubredId]);


  const selectedSubnet = subredList.find(s => String(s.id) === poolIdSubred);
  const isCMSubnet = selectedSubnet?.tipo === 'CM';

  // Filter lists based on selected CMTS
  const filteredSubredList = selectedFilterCmtsId === 'ALL'
    ? subredList
    : subredList.filter(s => s.idCmts === selectedFilterCmtsId);

  const filteredPoolList = selectedFilterCmtsId === 'ALL'
    ? poolList
    : poolList.filter(p => {
        const sub = subredList.find(s => s.id === p.idSubred);
        return sub && sub.idCmts === selectedFilterCmtsId;
      });

  // Filtered dropdown lists for safer forms
  const dropdownSubredList = selectedFilterCmtsId === 'ALL'
    ? subredList
    : subredList.filter(s => s.idCmts === selectedFilterCmtsId);

  const loadData = async () => {
    setLoading(true);
    const resC = await apiFetch<CMTS[]>('/api/red/cmts');
    const resS = await apiFetch<Subred[]>('/api/red/subredes');
    const resPo = await apiFetch<Pool[]>('/api/red/pools');
    const resPa = await apiFetch<Paquete[]>('/api/red/paquetes');
    const resB = await apiFetch<any[]>('/api/bootfiles');

    if (resC.success && resC.data) setCmtsList(resC.data);
    if (resS.success && resS.data) setSubredList(resS.data);
    if (resPo.success && resPo.data) setPoolList(resPo.data);
    if (resPa.success && resPa.data) setPaqueteList(resPa.data);
    if (resB.success && resB.data) {
      const compiledOnly = resB.data.filter(f => f.type?.includes('.bin') || f.name?.endsWith('.bin'));
      setBootfilesList(compiledOnly);
    }

    if (!resC.success || !resS.success) {
      showToast('Error al actualizar topología de red.', 'error');
    }
    setLoading(false);
  };

  useEffect(() => {
    loadData();
  }, []);

  useEffect(() => {
    if (paqClassMode === 'auto' && paqDown && paqUp) {
      const downStr = parseInt(paqDown) >= 1024 ? `${(parseInt(paqDown) / 1024).toFixed(0)}M` : `${paqDown}K`;
      const upStr = parseInt(paqUp) >= 1024 ? `${(parseInt(paqUp) / 1024).toFixed(0)}M` : `${paqUp}K`;
      setPaqClientClass(`cpe-${downStr}-${upStr}`);
    }
  }, [paqDown, paqUp, paqClassMode]);

  // Dynamic IPAM Autocomplete & Validation for New Pool Form
  useEffect(() => {
    if (editingPoolId === null && poolIdSubred) {
      const selectedSub = subredList.find(s => String(s.id) === poolIdSubred);
      if (selectedSub) {
        try {
          const { firstUsable, lastUsable } = parseCidr(selectedSub.cidr);
          
          const occupied = poolList
            .filter(p => p.idSubred === selectedSub.id)
            .map(p => ({
              start: ipToNum(p.rangoInicio),
              end: ipToNum(p.rangoFin)
            }));
            
          const gaps = getAvailableGaps(firstUsable, lastUsable, occupied);
          if (gaps.length > 0) {
            setPoolInicio(numToIp(gaps[0].start));
            setPoolFin(numToIp(gaps[0].end));
          } else {
            showToast('⚠️ Esta subred ya está completamente asignada a otros pools.', 'error');
            setPoolInicio('');
            setPoolFin('');
          }
        } catch (err) {
          console.error('Error calculating subnet boundaries:', err);
        }
      }
    }
  }, [poolIdSubred, poolList, editingPoolId]);

  // CMTS Handlers
  const handleCreateCmts = async (e: React.FormEvent) => {
    e.preventDefault();
    const payload: CMTS = {
      nombre: cmtsNombre.trim(),
      ipControl: cmtsIp.trim(),
      comunidadSnmp: cmtsSnmp.trim() || null,
    };
    if (editingCmtsId) {
      const res = await apiFetch(`/api/red/cmts/${editingCmtsId}`, { method: 'PUT', body: JSON.stringify(payload) });
      if (res.success) {
        showToast('Nodo CMTS actualizado con éxito.', 'success');
        handleCancelEditCmts();
        loadData();
      } else {
        showToast(res.error || 'Error al actualizar CMTS.', 'error');
      }
    } else {
      const res = await apiFetch('/api/red/cmts', { method: 'POST', body: JSON.stringify(payload) });
      if (res.success) {
        showToast(res.data?.message || 'Nodo CMTS creado con éxito.', 'success');
        setCmtsNombre('');
        setCmtsIp('');
        setCmtsSnmp('');
        loadData();
      } else {
        showToast(res.error || 'Error al guardar CMTS.', 'error');
      }
    }
  };

  const handleEditCmtsClick = (c: CMTS) => {
    setEditingCmtsId(c.id!);
    setCmtsNombre(c.nombre);
    setCmtsIp(c.ipControl);
    setCmtsSnmp(c.comunidadSnmp || '');
  };

  const handleCancelEditCmts = () => {
    setEditingCmtsId(null);
    setCmtsNombre('');
    setCmtsIp('');
    setCmtsSnmp('');
  };

  const handleDeleteCmts = async (id: number) => {
    if (!window.confirm('¿Eliminar CMTS? Se perderán subredes hijas si no se borran primero.')) return;
    const res = await apiFetch(`/api/red/cmts/${id}`, { method: 'DELETE' });
    if (res.success) {
      showToast('CMTS removido.', 'success');
      if (editingCmtsId === id) handleCancelEditCmts();
      loadData();
    } else {
      showToast(res.error || 'Conflicto de dependencias en la base de datos.', 'error');
    }
  };

  // Subred Handlers
  const handleCreateSubred = async (e: React.FormEvent) => {
    e.preventDefault();
    const payload: Subred = {
      idCmts: parseInt(subIdCmts),
      nombre: subNombre.trim(),
      cidr: subCidr.trim(),
      gateway: subGw.trim(),
      tipo: subTipo,
    };
    if (editingSubredId) {
      const res = await apiFetch(`/api/red/subredes/${editingSubredId}`, { method: 'PUT', body: JSON.stringify(payload) });
      if (res.success) {
        showToast('Subred actualizada con éxito.', 'success');
        handleCancelEditSubred();
        loadData();
      } else {
        showToast(res.error || 'Error al actualizar subred.', 'error');
      }
    } else {
      const res = await apiFetch('/api/red/subredes', { method: 'POST', body: JSON.stringify(payload) });
      if (res.success) {
        showToast('Subred asignada con éxito.', 'success');
        setSubIdCmts('');
        setSubNombre('');
        setSubCidr('');
        setSubGateway('');
        setSubTipo('CM');
        loadData();
      } else {
        showToast(res.error || 'Error de red CIDR.', 'error');
      }
    }
  };

  const handleEditSubredClick = (s: Subred) => {
    setEditingSubredId(s.id!);
    setSubIdCmts(String(s.idCmts));
    setSubNombre(s.nombre);
    setSubCidr(s.cidr);
    setSubGateway(s.gateway);
    setSubTipo(s.tipo || 'CM');
  };

  const handleCancelEditSubred = () => {
    setEditingSubredId(null);
    setSubIdCmts('');
    setSubNombre('');
    setSubCidr('');
    setSubGateway('');
    setSubTipo('CM');
  };

  const handleDeleteSubred = async (id: number) => {
    if (!window.confirm('¿Eliminar subred?')) return;
    const res = await apiFetch(`/api/red/subredes/${id}`, { method: 'DELETE' });
    if (res.success) {
      showToast('Subred eliminada.', 'success');
      if (editingSubredId === id) handleCancelEditSubred();
      loadData();
    } else {
      showToast(res.error || 'Elimine primero los pools DHCP asociados.', 'error');
    }
  };

  // Pool Handlers
  const handleCreatePool = async (e: React.FormEvent) => {
    e.preventDefault();
    setPoolFormError(null);
    const payload: Pool = {
      idSubred: parseInt(poolIdSubred),
      rangoInicio: poolInicio.trim(),
      rangoFin: poolFin.trim(),
      clientClass: isCMSubnet ? null : (poolClientClass || null),
      esEstatico: poolEsEstatico,
    };
    if (editingPoolId) {
      const res = await apiFetch(`/api/red/pools/${editingPoolId}`, { method: 'PUT', body: JSON.stringify(payload) });
      if (res.success) {
        showToast('Pool DHCP actualizado con éxito.', 'success');
        handleCancelEditPool();
        loadData();
      } else {
        setPoolFormError(res.error || 'Error al actualizar pool.');
        showToast(res.error || 'Error al actualizar pool.', 'error');
      }
    } else {
      const res = await apiFetch('/api/red/pools', { method: 'POST', body: JSON.stringify(payload) });
      if (res.success) {
        showToast('Pool DHCP creado.', 'success');
        setPoolIdSubred('');
        setPoolInicio('');
        setPoolFin('');
        setPoolClientClass('');
        setPoolEsEstatico(false);
        setIsCreatingNewClass(false);
        setPoolFormError(null);
        loadData();
      } else {
        setPoolFormError(res.error || 'Rango de IPs incorrecto.');
        showToast(res.error || 'Rango de IPs incorrecto.', 'error');
      }
    }
  };

  const handleEditPoolClick = (p: Pool) => {
    setEditingPoolId(p.id!);
    setPoolIdSubred(p.idSubred ? String(p.idSubred) : '');
    setPoolInicio(p.rangoInicio);
    setPoolFin(p.rangoFin);
    setPoolClientClass(p.clientClass || '');
    setPoolEsEstatico(p.esEstatico || false);
    setPoolFormError(null);
  };

  const handleCancelEditPool = () => {
    setEditingPoolId(null);
    setPoolIdSubred('');
    setPoolInicio('');
    setPoolFin('');
    setPoolClientClass('');
    setPoolEsEstatico(false);
    setIsCreatingNewClass(false);
    setPoolFormError(null);
  };

  const handleDeletePool = async (id: number) => {
    if (!window.confirm('¿Remover pool DHCP?')) return;
    const res = await apiFetch(`/api/red/pools/${id}`, { method: 'DELETE' });
    if (res.success) {
      showToast('Pool DHCP removido.', 'success');
      if (editingPoolId === id) handleCancelEditPool();
      loadData();
    } else {
      showToast(res.error || 'Error al borrar rango.', 'error');
    }
  };

  // Paquete Handlers
  const handleCreatePaquete = async (e: React.FormEvent) => {
    e.preventDefault();
    const payload: Paquete = {
      nombre: paqNombre.trim(),
      velocidadBajadaKbps: parseInt(paqDown),
      velocidadSubidaKbps: parseInt(paqUp),
      limiteDispositivos: parseInt(paqLimit),
      bootfile: paqBootfile || null,
      dhcp4ClientClass: paqClientClass.trim() || null,
    };
    if (editingPaqueteId) {
      const res = await apiFetch(`/api/red/paquetes/${editingPaqueteId}`, { method: 'PUT', body: JSON.stringify(payload) });
      if (res.success) {
        showToast('Plan de velocidad actualizado.', 'success');
        handleCancelEditPaquete();
        loadData();
      } else {
        showToast(res.error || 'Error al actualizar paquete.', 'error');
      }
    } else {
      const res = await apiFetch('/api/red/paquetes', { method: 'POST', body: JSON.stringify(payload) });
      if (res.success) {
        showToast('Plan de velocidad creado.', 'success');
        setPaqNombre('');
        setPaqDown('');
        setPaqUp('');
        setPaqLimit('1');
        setPaqBootfile('');
        setPaqClientClass('');
        setPaqClassMode('auto');
        loadData();
      } else {
        showToast(res.error || 'Error al guardar paquete.', 'error');
      }
    }
  };

  const handleEditPaqueteClick = (pa: Paquete) => {
    setEditingPaqueteId(pa.id!);
    setPaqNombre(pa.nombre);
    setPaqDown(String(pa.velocidadBajadaKbps));
    setPaqUp(String(pa.velocidadSubidaKbps));
    setPaqLimit(String(pa.limiteDispositivos || 1));
    setPaqBootfile(pa.bootfile || '');
    setPaqClientClass(pa.dhcp4ClientClass || '');
    
    // Detectar si la clase actual es autogenerada o personalizada
    if (pa.dhcp4ClientClass) {
      const downStr = pa.velocidadBajadaKbps >= 1024 ? `${(pa.velocidadBajadaKbps / 1024).toFixed(0)}M` : `${pa.velocidadBajadaKbps}K`;
      const upStr = pa.velocidadSubidaKbps >= 1024 ? `${(pa.velocidadSubidaKbps / 1024).toFixed(0)}M` : `${pa.velocidadSubidaKbps}K`;
      const expectedAuto = `cpe-${downStr}-${upStr}`;
      if (pa.dhcp4ClientClass === expectedAuto) {
        setPaqClassMode('auto');
      } else {
        setPaqClassMode('custom');
      }
    } else {
      setPaqClassMode('auto');
    }
  };

  const handleCancelEditPaquete = () => {
    setEditingPaqueteId(null);
    setPaqNombre('');
    setPaqDown('');
    setPaqUp('');
    setPaqLimit('1');
    setPaqBootfile('');
    setPaqClientClass('');
    setPaqClassMode('auto');
  };

  const handleDeletePaquete = async (id: number) => {
    if (!window.confirm('¿Desea borrar este plan de velocidad?')) return;
    const res = await apiFetch(`/api/red/paquetes/${id}`, { method: 'DELETE' });
    if (res.success) {
      showToast('Plan borrado con éxito.', 'success');
      if (editingPaqueteId === id) handleCancelEditPaquete();
      loadData();
    } else {
      showToast(res.error || 'Hay clientes activos que dependen de este plan.', 'error');
    }
  };

  return (
    <div>
      {/* Sistema de Sub-pestañas Internas (Vercel-style) */}
      <div className="sub-tabs-container">
        <button 
          type="button"
          onClick={() => setActiveSubTab('cmts')} 
          className={`sub-tab-btn ${activeSubTab === 'cmts' ? 'active' : ''}`}
        >
          Infraestructura CMTS
        </button>
        <button 
          type="button"
          onClick={() => setActiveSubTab('ipam')} 
          className={`sub-tab-btn ${activeSubTab === 'ipam' ? 'active' : ''}`}
        >
          Direccionamiento IP (IPAM)
        </button>
        <button 
          type="button"
          onClick={() => setActiveSubTab('planes')} 
          className={`sub-tab-btn ${activeSubTab === 'planes' ? 'active' : ''}`}
        >
          Planes Comerciales
        </button>
      </div>

      {activeSubTab === 'cmts' && (
        <div className="animate-slide-up" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px', marginBottom: '32px' }}>
          {/* SECCIÓN 1: CMTSs */}
          <div className="panel" style={{ marginBottom: 0 }}>
            <div className="panel-header">
              <div className="panel-title">
                {editingCmtsId ? <Edit size={16} /> : <Plus size={16} />} {editingCmtsId ? "Modificar Nodo CMTS" : "Nuevo Nodo CMTS"}
              </div>
            </div>
            <form onSubmit={handleCreateCmts}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                <div className="form-group">
                  <label>Nombre del Nodo CMTS *</label>
                  <input type="text" placeholder="Ej: CMTS Mendoza Centro" value={cmtsNombre} onChange={e => setCmtsNombre(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label>IP de Gestión de Control *</label>
                  <input type="text" placeholder="Ej: 10.0.0.1" value={cmtsIp} onChange={e => setCmtsIp(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label>Comunidad SNMP v2c *</label>
                  <input type="text" placeholder="Ej: public" value={cmtsSnmp} onChange={e => setCmtsSnmp(e.target.value)} required />
                </div>
              </div>
              {editingCmtsId ? (
                <div style={{ display: 'flex', gap: '8px', marginTop: '16px' }}>
                  <button type="submit" className="btn btn-primary">Guardar Cambios</button>
                  <button type="button" className="btn" onClick={handleCancelEditCmts}>Cancelar</button>
                </div>
              ) : (
                <button type="submit" className="btn btn-primary" style={{ marginTop: '16px' }}>Crear Nodo CMTS</button>
              )}
            </form>
          </div>

          <div className="panel" style={{ marginBottom: 0, display: 'flex', flexDirection: 'column' }}>
            <div className="panel-header"><div className="panel-title">Nodos CMTS Activos</div></div>
            <div className="table-responsive" style={{ maxHeight: '250px', overflowY: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Nombre</th>
                    <th>IP Gestión</th>
                    <th style={{ textAlign: 'center', width: '120px' }}>Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? <tr><td colSpan={4}>Cargando...</td></tr> : cmtsList.length === 0 ? <tr><td colSpan={4} style={{ opacity: 0.5 }}>Ninguno.</td></tr> : cmtsList.map(c => (
                    <tr key={c.id}>
                      <td><strong>{c.id}</strong></td>
                      <td>{c.nombre}</td>
                      <td><code>{c.ipControl}</code></td>
                      <td style={{ textAlign: 'center' }}>
                        <div style={{ display: 'flex', gap: '6px', justifyContent: 'center' }}>
                          <button onClick={() => handleEditCmtsClick(c)} className="btn btn-warning" style={{ padding: '4px 8px' }} title="Editar"><Edit size={12} /></button>
                          <button onClick={() => handleDeleteCmts(c.id!)} className="btn btn-danger" style={{ padding: '4px 8px' }} title="Eliminar"><Trash2 size={12} /></button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {activeSubTab === 'ipam' && (
        <div className="animate-slide-up" style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          
          {/* BARRA DE FILTRO GLOBAL DE CMTS (Select Premium) */}
          <div className="panel" style={{ 
            padding: '16px 24px', 
            marginBottom: 0, 
            display: 'flex', 
            alignItems: 'center', 
            justifyContent: 'space-between',
            flexWrap: 'wrap',
            gap: '16px'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <div style={{
                background: 'rgba(0, 180, 216, 0.1)',
                color: 'var(--primary-color)',
                padding: '8px',
                borderRadius: '0px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center'
              }}>
                <Network size={18} />
              </div>
              <div>
                <div className="panel-title" style={{ fontSize: '15px', fontWeight: '600' }}>Filtrar Topología por CMTS</div>
                <p style={{ margin: '2px 0 0 0', fontSize: '11px', color: 'var(--text-muted)' }}>
                  Aísla las subredes y rangos DHCP por nodo para evitar confusiones al crecer tu planta
                </p>
              </div>
            </div>
            
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <label style={{ fontSize: '11px', fontFamily: 'var(--font-mono)', color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Seleccionar CMTS:</label>
              <select 
                value={selectedFilterCmtsId} 
                onChange={(e) => {
                  const val = e.target.value;
                  setSelectedFilterCmtsId(val === 'ALL' ? 'ALL' : parseInt(val));
                }}
                className="premium-select"
                style={{ padding: '6px 12px', fontSize: '13px', minWidth: '220px' }}
              >
                <option value="ALL">🌐 TODOS LOS NODOS CMTS</option>
                {cmtsList.map(c => (
                  <option key={c.id} value={c.id}>🏢 {c.nombre}</option>
                ))}
              </select>
            </div>
          </div>

          {/* SECCIÓN 2: SUBREDES */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px' }}>
            <div className="panel" style={{ marginBottom: 0 }}>
              <div className="panel-header">
                <div className="panel-title">
                  {editingSubredId ? <Edit size={16} /> : <Plus size={16} />} {editingSubredId ? "Modificar Subred" : "Asignar Nueva Subred"}
                </div>
              </div>
              <form onSubmit={handleCreateSubred}>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                  <div className="form-group">
                    <label>Asociar a CMTS *</label>
                    <select value={subIdCmts} onChange={e => setSubIdCmts(e.target.value)} required>
                      <option value="">-- Seleccionar CMTS --</option>
                      {cmtsList.map(c => <option key={c.id} value={c.id}>{c.nombre}</option>)}
                    </select>
                  </div>
                  <div className="form-group">
                    <label>Nombre de Subred *</label>
                    <input type="text" placeholder="Ej: HFC Clientes Residenciales" value={subNombre} onChange={e => setSubNombre(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label>Rango CIDR *</label>
                    <input type="text" placeholder="Ej: 192.168.10.0/24" value={subCidr} onChange={e => setSubCidr(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label>Puerta de Enlace (Gateway) *</label>
                    <input type="text" placeholder="Ej: 192.168.10.1" value={subGw} onChange={e => setSubGateway(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label>Tipo de Subred *</label>
                    <select value={subTipo} onChange={e => setSubTipo(e.target.value)} required style={{ width: '100%' }}>
                      <option value="CM">CM (Gestión de Cablemódems)</option>
                      <option value="CPE">CPE (Navegación de Clientes)</option>
                    </select>
                  </div>
                </div>
                {editingSubredId ? (
                  <div style={{ display: 'flex', gap: '8px', marginTop: '16px' }}>
                    <button type="submit" className="btn btn-primary">Guardar Cambios</button>
                    <button type="button" className="btn" onClick={handleCancelEditSubred}>Cancelar</button>
                  </div>
                ) : (
                  <button type="submit" className="btn btn-primary" style={{ marginTop: '16px' }}>Asignar Subred</button>
                )}
              </form>
            </div>

            <div className="panel" style={{ marginBottom: 0, display: 'flex', flexDirection: 'column' }}>
              <div className="panel-header"><div className="panel-title">Subredes IP (Scopes Activos)</div></div>
              <div className="table-responsive" style={{ maxHeight: '310px', overflowY: 'auto' }}>
                <table>
                  <thead>
                    <tr>
                      <th>ID</th>
                      <th>Datos de Subred</th>
                      <th>Tipo</th>
                      <th>CMTS Asociado</th>
                      <th style={{ textAlign: 'center', width: '100px' }}>Acciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {loading ? <tr><td colSpan={5}>Cargando...</td></tr> : filteredSubredList.length === 0 ? <tr><td colSpan={5} style={{ opacity: 0.5 }}>Ninguno.</td></tr> : filteredSubredList.map(s => {
                      const parentCmts = cmtsList.find(c => c.id === s.idCmts);
                      return (
                        <tr key={s.id}>
                          <td><strong>{s.id}</strong></td>
                          <td>
                            <div><b>{s.nombre}</b></div>
                            <code>{s.cidr}</code> <span style={{ opacity: 0.5 }}>GW: {s.gateway}</span>
                          </td>
                          <td>
                            <span className={`badge ${s.tipo === 'CM' ? 'badge-suspended' : 'badge-active'}`}>
                              {s.tipo}
                            </span>
                          </td>
                          <td>{parentCmts ? parentCmts.nombre : <span style={{ opacity: 0.3 }}>N/A</span>}</td>
                          <td style={{ textAlign: 'center' }}>
                            <div style={{ display: 'flex', gap: '6px', justifyContent: 'center' }}>
                              <button onClick={() => handleEditSubredClick(s)} className="btn btn-warning" style={{ padding: '4px 8px' }} title="Editar"><Edit size={12} /></button>
                              <button onClick={() => handleDeleteSubred(s.id!)} className="btn btn-danger" style={{ padding: '4px 8px' }} title="Eliminar"><Trash2 size={12} /></button>
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          {/* SECCIÓN 3: POOLS DHCP */}
          <div style={{ display: 'grid', gridTemplateColumns: '1.1fr 1.5fr', gap: '24px' }}>
            <div className="panel" style={{ marginBottom: 0 }}>
              <div className="panel-header">
                <div className="panel-title">
                  {editingPoolId ? <Edit size={16} /> : <Plus size={16} />} {editingPoolId ? "Modificar Rango Pool DHCP" : "Nuevo Rango IP (Pool DHCP)"}
                </div>
              </div>
              <form onSubmit={handleCreatePool}>
                {poolFormError && (
                  <div style={{
                    background: 'rgba(239, 68, 68, 0.08)',
                    border: '1px solid rgba(239, 68, 68, 0.25)',
                    color: '#f87171',
                    padding: '12px 16px',
                    borderRadius: '0px',
                    marginBottom: '16px',
                    fontSize: '13px',
                    display: 'flex',
                    alignItems: 'flex-start',
                    gap: '10px',
                    lineHeight: '1.4',
                    position: 'relative',
                    boxShadow: '0 4px 12px rgba(239, 68, 68, 0.05)',
                  }}>
                    <div style={{ marginTop: '2px', display: 'flex', alignItems: 'center' }}>
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                        <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
                      </svg>
                    </div>
                    <div style={{ flex: 1 }}>
                      <strong style={{ fontWeight: '600', display: 'block', marginBottom: '2px', color: '#ef4444' }}>Error de Validación de IPAM</strong>
                      {poolFormError}
                    </div>
                    <button 
                      type="button" 
                      onClick={() => setPoolFormError(null)} 
                      style={{
                        background: 'none',
                        border: 'none',
                        color: '#ef4444',
                        cursor: 'pointer',
                        fontSize: '16px',
                        padding: '0 4px',
                        opacity: 0.8,
                        fontWeight: 'bold',
                        display: 'flex',
                        alignItems: 'center',
                        marginTop: '-2px'
                      }}
                      title="Cerrar"
                    >
                      &times;
                    </button>
                  </div>
                )}

                <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                  <div className="form-group">
                    <label>Vincular a Subred *</label>
                    <select value={poolIdSubred} onChange={e => setPoolIdSubred(e.target.value)} required>
                      <option value="">-- Seleccionar Subred --</option>
                      {dropdownSubredList.map(s => <option key={s.id} value={s.id}>{s.nombre} ({s.cidr})</option>)}
                    </select>
                  </div>
                  <div className="form-group">
                    <label>IP de Inicio de Pool *</label>
                    <input type="text" placeholder="Ej: 192.168.10.10" value={poolInicio} onChange={e => setPoolInicio(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label>IP de Fin de Pool *</label>
                    <input type="text" placeholder="Ej: 192.168.10.250" value={poolFin} onChange={e => setPoolFin(e.target.value)} required />
                  </div>
                  {isCMSubnet ? (
                    <div className="form-group" style={{ opacity: 0.7 }}>
                      <label>Grupo de Pools IP (Deshabilitado)</label>
                      <input type="text" value="-- No aplica para Gestión de Cablemodems (CM) --" disabled style={{ background: 'var(--border-color)', cursor: 'not-allowed' }} />
                      <p style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '4px' }}>
                        ℹ️ Las subredes de tipo <b>CM (Gestión de Cablemodems)</b> no admiten clases ni grupos; sus rangos son generales para aprovisionamiento físico.
                      </p>
                    </div>
                  ) : (
                    <div className="form-group">
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px' }}>
                        <label style={{ margin: 0 }}>Grupo de Pools IP / Clase (Opcional)</label>
                        <label style={{ margin: 0, fontSize: '11px', display: 'inline-flex', alignItems: 'center', gap: '4px', cursor: 'pointer', color: 'var(--primary-color)', fontWeight: 'bold', userSelect: 'none' }}>
                          <input 
                            type="checkbox" 
                            checked={isCreatingNewClass} 
                            onChange={e => {
                              setIsCreatingNewClass(e.target.checked);
                              if (!e.target.checked) setPoolClientClass('');
                            }} 
                            style={{ width: '13px', height: '13px', margin: 0, cursor: 'pointer' }}
                          />
                          ✍️ Escribir nuevo
                        </label>
                      </div>
                      {isCreatingNewClass ? (
                        <input 
                          type="text" 
                          placeholder="Ej: cpe-dhcp-privadas" 
                          value={poolClientClass} 
                          onChange={e => setPoolClientClass(e.target.value)} 
                          required
                        />
                      ) : (
                        <select value={poolClientClass} onChange={e => setPoolClientClass(e.target.value)}>
                          <option value="">-- Sin clase (Por defecto) --</option>
                          {Array.from(new Set(poolList.map(p => p.clientClass).filter(Boolean))).map(cls => (
                            <option key={cls} value={cls!}>{cls}</option>
                          ))}
                          {Array.from(new Set(paqueteList.map(pa => pa.dhcp4ClientClass).filter(Boolean))).map(cls => (
                            <option key={cls} value={cls!}>{cls}</option>
                          ))}
                        </select>
                      )}
                    </div>
                  )}

                  <div className="form-group" style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '4px' }}>
                    <input 
                      type="checkbox" 
                      id="pool-estatico" 
                      checked={poolEsEstatico} 
                      onChange={e => setPoolEsEstatico(e.target.checked)} 
                      style={{ width: '16px', height: '16px', cursor: 'pointer', margin: 0 }}
                    />
                    <label htmlFor="pool-estatico" style={{ margin: 0, cursor: 'pointer', fontWeight: '500' }}>
                      📍 Reservar exclusivamente para IPs Estáticas / Fijas
                    </label>
                  </div>
                </div>

                {editingPoolId ? (
                  <div style={{ display: 'flex', gap: '8px', marginTop: '16px' }}>
                    <button type="submit" className="btn btn-primary">Guardar Cambios</button>
                    <button type="button" className="btn" onClick={handleCancelEditPool}>Cancelar</button>
                  </div>
                ) : (
                  <button type="submit" className="btn btn-primary" style={{ marginTop: '16px' }}>Crear Pool DHCP</button>
                )}
              </form>
            </div>

            <div className="panel" style={{ marginBottom: 0, display: 'flex', flexDirection: 'column' }}>
              <div className="panel-header"><div className="panel-title">Rangos DHCP Activos (IPAM Ranges)</div></div>
              <div className="table-responsive" style={{ maxHeight: '420px', overflowY: 'auto' }}>
                <table>
                  <thead>
                    <tr>
                      <th>ID</th>
                      <th>Rango de IPs</th>
                      <th>Vínculo Scope</th>
                      <th>Grupo / Clase</th>
                      <th>Tipo</th>
                      <th>Uso</th>
                      <th style={{ textAlign: 'center', width: '100px' }}>Acciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {loading ? <tr><td colSpan={7}>Cargando...</td></tr> : filteredPoolList.length === 0 ? <tr><td colSpan={7} style={{ opacity: 0.5 }}>Ninguno.</td></tr> : filteredPoolList.map(p => {
                      const sub = subredList.find(s => s.id === p.idSubred);
                      return (
                        <tr key={p.id}>
                          <td><strong>{p.id}</strong></td>
                          <td>
                            <code>{p.rangoInicio}</code> - <code>{p.rangoFin}</code>
                          </td>
                          <td>
                            {sub ? (
                              <div>
                                <b>{sub.nombre}</b>
                                <div style={{ fontSize: '10px', opacity: 0.6 }}>{sub.cidr}</div>
                              </div>
                            ) : <span style={{ opacity: 0.3 }}>N/A</span>}
                          </td>
                          <td>
                            {p.clientClass ? (
                              <span className="badge badge-active" style={{ fontSize: '11px' }}>🏷️ {p.clientClass}</span>
                            ) : (
                              <span style={{ opacity: 0.4, fontSize: '11px' }}>Global</span>
                            )}
                          </td>
                          <td>
                            <span className={`badge ${p.esEstatico ? 'badge-danger' : 'badge-stock'}`}>
                              {p.esEstatico ? 'Estática (Fija)' : 'Dinámica (DHCP)'}
                            </span>
                          </td>
                          <td>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                              <div style={{
                                width: '60px',
                                background: 'rgba(255,255,255,0.07)',
                                height: '6px',
                                borderRadius: '0px',
                                overflow: 'hidden',
                                position: 'relative'
                              }}>
                                <div style={{
                                  width: `${Math.min(100, ((p.ipsAsignadas || 0) / (p.totalIps || 1)) * 100)}%`,
                                  background: 'var(--primary-color)',
                                  height: '100%'
                                }} />
                              </div>
                              <span style={{ fontSize: '10px', opacity: 0.8, fontWeight: 'bold' }}>
                                {(((p.ipsAsignadas || 0) / (p.totalIps || 1)) * 100).toFixed(0)}%
                              </span>
                            </div>
                          </td>
                          <td style={{ textAlign: 'center' }}>
                            <div style={{ display: 'flex', gap: '6px', justifyContent: 'center' }}>
                              <button onClick={() => handleEditPoolClick(p)} className="btn btn-warning" style={{ padding: '4px 8px' }} title="Editar"><Edit size={12} /></button>
                              <button onClick={() => handleDeletePool(p.id!)} className="btn btn-danger" style={{ padding: '4px 8px' }} title="Eliminar"><Trash2 size={12} /></button>
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          </div>

        </div>
      )}

      {activeSubTab === 'planes' && (
        <div className="animate-slide-up" style={{ display: 'grid', gridTemplateColumns: '1fr 1.4fr', gap: '24px', marginBottom: '32px' }}>
          {/* SECCIÓN 4: PAQUETES VELOCIDAD */}
          <div className="panel" style={{ marginBottom: 0 }}>
            <div className="panel-header">
              <div className="panel-title">
                {editingPaqueteId ? <Edit size={16} /> : <Plus size={16} />} {editingPaqueteId ? "Modificar Plan de Velocidad" : "Registrar Plan de Velocidad"}
              </div>
            </div>
            <form onSubmit={handleCreatePaquete}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                <div className="form-group">
                  <label>Nombre del Plan Comercial *</label>
                  <input type="text" placeholder="Ej: Plan Fibra 100 Mbps" value={paqNombre} onChange={e => setPaqNombre(e.target.value)} required />
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label>Velocidad de Bajada (Kbps) *</label>
                    <input type="number" placeholder="Ej: 102400" value={paqDown} onChange={e => setPaqDown(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label>Velocidad de Subida (Kbps) *</label>
                    <input type="number" placeholder="Ej: 20480" value={paqUp} onChange={e => setPaqUp(e.target.value)} required />
                  </div>
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label>Límite de Dispositivos (Leases) *</label>
                    <input type="number" placeholder="Ej: 2" value={paqLimit} onChange={e => setPaqLimit(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label>Archivo de Arranque (Bootfile) *</label>
                    <select value={paqBootfile} onChange={e => setPaqBootfile(e.target.value)} required>
                      <option value="">-- Seleccionar Archivo --</option>
                      {bootfilesList.map(b => (
                        <option key={b.name} value={b.name}>{b.name}</option>
                      ))}
                    </select>
                  </div>
                </div>
                <div className="form-group">
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                    <label style={{ margin: 0 }}>Clase de Cliente DHCP (dhcp4ClientClass) *</label>
                  </div>
                  
                  {/* Selector de Modo de Clase (Premium Segmented Control) */}
                  <div style={{ 
                    display: 'grid', 
                    gridTemplateColumns: '1fr 1fr 1fr', 
                    background: 'rgba(255,255,255,0.03)', 
                    border: '1px solid var(--border-color)', 
                    borderRadius: '4px',
                    padding: '3px',
                    marginBottom: '10px'
                  }}>
                    <button
                      type="button"
                      onClick={() => setPaqClassMode('auto')}
                      style={{
                        padding: '6px 8px',
                        fontSize: '11px',
                        border: 'none',
                        borderRadius: '3px',
                        cursor: 'pointer',
                        background: paqClassMode === 'auto' ? 'var(--accent)' : 'transparent',
                        color: paqClassMode === 'auto' ? '#fff' : 'var(--text-muted)',
                        fontWeight: paqClassMode === 'auto' ? '600' : 'normal',
                        transition: 'all 0.15s ease'
                      }}
                    >
                      ⚡ Auto-generar
                    </button>
                    <button
                      type="button"
                      onClick={() => setPaqClassMode('select')}
                      style={{
                        padding: '6px 8px',
                        fontSize: '11px',
                        border: 'none',
                        borderRadius: '3px',
                        cursor: 'pointer',
                        background: paqClassMode === 'select' ? 'var(--accent)' : 'transparent',
                        color: paqClassMode === 'select' ? '#fff' : 'var(--text-muted)',
                        fontWeight: paqClassMode === 'select' ? '600' : 'normal',
                        transition: 'all 0.15s ease'
                      }}
                    >
                      📁 Seleccionar
                    </button>
                    <button
                      type="button"
                      onClick={() => setPaqClassMode('custom')}
                      style={{
                        padding: '6px 8px',
                        fontSize: '11px',
                        border: 'none',
                        borderRadius: '3px',
                        cursor: 'pointer',
                        background: paqClassMode === 'custom' ? 'var(--accent)' : 'transparent',
                        color: paqClassMode === 'custom' ? '#fff' : 'var(--text-muted)',
                        fontWeight: paqClassMode === 'custom' ? '600' : 'normal',
                        transition: 'all 0.15s ease'
                      }}
                    >
                      ✍️ Manual
                    </button>
                  </div>

                  {/* Input condicional según el modo */}
                  {paqClassMode === 'auto' && (
                    <input 
                      type="text" 
                      value={paqClientClass} 
                      disabled 
                      style={{ background: 'rgba(255,255,255,0.03)', opacity: 0.8, color: 'var(--text-color)', cursor: 'not-allowed' }} 
                    />
                  )}

                  {paqClassMode === 'select' && (
                    <select 
                      value={paqClientClass} 
                      onChange={e => setPaqClientClass(e.target.value)}
                      required
                    >
                      <option value="">-- Seleccionar Clase Existente --</option>
                      {Array.from(new Set([
                        ...poolList.map(p => p.clientClass),
                        ...paqueteList.map(pa => pa.dhcp4ClientClass)
                      ].filter(Boolean))).map(cls => (
                        <option key={cls} value={cls!}>{cls}</option>
                      ))}
                    </select>
                  )}

                  {paqClassMode === 'custom' && (
                    <input 
                      type="text" 
                      placeholder="Ej: cpe-100megas-vip" 
                      value={paqClientClass} 
                      onChange={e => setPaqClientClass(e.target.value)} 
                      required
                    />
                  )}

                  <p style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '6px' }}>
                    ℹ️ Esta clase asocia automáticamente el archivo de arranque (Bootfile) y limita las velocidades a nivel DHCP/DOCSIS. Varios pools y servicios pueden reutilizar la misma clase.
                  </p>
                </div>
              </div>
              {editingPaqueteId ? (
                <div style={{ display: 'flex', gap: '8px', marginTop: '16px' }}>
                  <button type="submit" className="btn btn-primary">Guardar Cambios</button>
                  <button type="button" className="btn" onClick={handleCancelEditPaquete}>Cancelar</button>
                </div>
              ) : (
                <button type="submit" className="btn btn-primary" style={{ marginTop: '16px' }}>Crear Plan Comercial</button>
              )}
            </form>
          </div>

          <div className="panel" style={{ marginBottom: 0, display: 'flex', flexDirection: 'column' }}>
            <div className="panel-header"><div className="panel-title">Planes Comerciales Disponibles</div></div>
            <div className="table-responsive" style={{ maxHeight: '420px', overflowY: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Plan Comercial</th>
                    <th>Velocidades (D/U)</th>
                    <th>Archivo de Arranque</th>
                    <th>Clase DHCP</th>
                    <th style={{ textAlign: 'center', width: '100px' }}>Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? <tr><td colSpan={6}>Cargando...</td></tr> : paqueteList.length === 0 ? <tr><td colSpan={6} style={{ opacity: 0.5 }}>Ninguno.</td></tr> : paqueteList.map(pa => (
                    <tr key={pa.id}>
                      <td><strong>{pa.id}</strong></td>
                      <td>
                        <div><b>{pa.nombre}</b></div>
                        <div style={{ fontSize: '10px', opacity: 0.6 }}>Límite: {pa.limiteDispositivos} leases</div>
                      </td>
                      <td>
                        <code>{(pa.velocidadBajadaKbps / 1024).toFixed(0)}M</code> / <code>{(pa.velocidadSubidaKbps / 1024).toFixed(0)}M</code>
                      </td>
                      <td>
                        {pa.bootfile ? (
                          <span className="badge badge-stock" style={{ fontSize: '11px', fontFamily: 'monospace', padding: '4px 8px' }}>
                            📄 {pa.bootfile}
                          </span>
                        ) : (
                          <span style={{ opacity: 0.4, fontSize: '11px' }}>Ninguno</span>
                        )}
                      </td>
                      <td>
                        {pa.dhcp4ClientClass ? (
                          <span className="badge badge-active" title="Identificador de grupo de direccionamiento IP asignado">
                            🏷️ {pa.dhcp4ClientClass}
                          </span>
                        ) : (
                          <span style={{ opacity: 0.3 }}>Ninguno</span>
                        )}
                      </td>
                      <td style={{ textAlign: 'center' }}>
                        <div style={{ display: 'flex', gap: '6px', justifyContent: 'center' }}>
                          <button onClick={() => handleEditPaqueteClick(pa)} className="btn btn-warning" style={{ padding: '4px 8px' }} title="Editar"><Edit size={12} /></button>
                          <button onClick={() => handleDeletePaquete(pa.id!)} className="btn btn-danger" style={{ padding: '4px 8px' }} title="Eliminar"><Trash2 size={12} /></button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default RedView;
