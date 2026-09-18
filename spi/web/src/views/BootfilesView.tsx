import React, { useState, useEffect, useRef } from 'react';
import { UploadCloud, FileText, Database, Trash2, File, Network } from 'lucide-react';
import { apiFetch, TftpFile } from '../utils/api';

interface BootfilesViewProps {
  showToast: (msg: string, type: 'success' | 'error') => void;
}

export const BootfilesView: React.FC<BootfilesViewProps> = ({ showToast }) => {
  const [files, setFiles] = useState<TftpFile[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [uploading, setUploading] = useState<boolean>(false);
  const [dragActive, setDragActive] = useState<boolean>(false);

  // Viewer states
  const [selectedFileName, setSelectedFileName] = useState<string | null>(null);
  const [selectedFileContent, setSelectedFileNameContent] = useState<string | null>(null);
  const [loadingContent, setLoadingContent] = useState<boolean>(false);

  const fileInputRef = useRef<HTMLInputElement>(null);

  const fetchFiles = async () => {
    setLoading(true);
    const res = await apiFetch<TftpFile[]>('/api/bootfiles');
    if (res.success && res.data) {
      setFiles(res.data);
    } else {
      showToast('No se pudo leer la lista de archivos TFTP.', 'error');
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchFiles();
  }, []);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      await uploadFile(e.target.files[0]);
    }
  };

  const uploadFile = async (file: File) => {
    const ext = file.name.split('.').pop()?.toLowerCase();
    if (ext !== 'bin' && ext !== 'bat' && ext !== 'txt' && ext !== 'key') {
      showToast('Solo se permiten archivos con extensión .bin, .bat, .txt o .key.', 'error');
      return;
    }

    setUploading(true);
    const formData = new FormData();
    formData.append('file', file);

    try {
      const token = localStorage.getItem('token');
      const response = await fetch('/api/bootfiles/upload', {
        method: 'POST',
        headers: token ? { 'Authorization': `Bearer ${token}` } : {},
        body: formData
      });

      const resData = await response.json();

      if (response.ok) {
        showToast(resData.message || 'Archivo subido correctamente.', 'success');
        fetchFiles();
      } else {
        showToast(resData.error || 'No se pudo subir el archivo.', 'error');
      }
    } catch (err) {
      showToast('Error de red al intentar subir el archivo.', 'error');
    } finally {
      setUploading(false);
    }
  };

  const handleDrag = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.type === "dragenter" || e.type === "dragover") {
      setDragActive(true);
    } else if (e.type === "dragleave") {
      setDragActive(false);
    }
  };

  const handleDrop = async (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      await uploadFile(e.dataTransfer.files[0]);
    }
  };

  const handleViewContent = async (file: TftpFile) => {
    const ext = file.name.split('.').pop()?.toLowerCase();
    if (ext !== 'txt' && ext !== 'bat' && ext !== 'key') {
      setSelectedFileName(file.name);
      setSelectedFileNameContent(`El archivo '${file.name}' es de tipo binario/compilado.\nNo se puede previsualizar como texto plano.`);
      return;
    }

    setLoadingContent(true);
    setSelectedFileName(file.name);
    const res = await apiFetch<{ filename: string; content: string }>(`/api/bootfiles/${file.name}`);
    if (res.success && res.data) {
      setSelectedFileNameContent(res.data.content);
    } else {
      showToast('Error al leer el archivo en el servidor.', 'error');
      setSelectedFileNameContent(null);
    }
    setLoadingContent(false);
  };

  const handleDelete = async (e: React.MouseEvent, fileName: string) => {
    e.stopPropagation();
    
    if (!window.confirm(`¿Está seguro de que desea eliminar el archivo '${fileName}' permanentemente del servidor TFTP?`)) {
      return;
    }

    const res = await apiFetch(`/api/bootfiles/${fileName}`, {
      method: 'DELETE',
    });

    if (res.success) {
      showToast('Archivo eliminado del TFTP.', 'success');
      if (selectedFileName === fileName) {
        setSelectedFileName(null);
        setSelectedFileNameContent(null);
      }
      fetchFiles();
    } else {
      showToast(res.error || 'Error al eliminar archivo.', 'error');
    }
  };

  const getFileBadge = (filename: string) => {
    const ext = filename.split('.').pop()?.toLowerCase();
    switch (ext) {
      case 'bin':
        return <span className="badge badge-active" style={{ fontSize: '10px', borderRadius: '4px', background: 'rgba(0,180,216,0.1)', color: '#00b4d8', border: '1px solid rgba(0,180,216,0.2)', padding: '2px 6px' }}>BIN</span>;
      case 'bat':
        return <span className="badge badge-warning" style={{ fontSize: '10px', borderRadius: '4px', background: 'rgba(245,158,11,0.1)', color: '#f59e0b', border: '1px solid rgba(245,158,11,0.2)', padding: '2px 6px' }}>BAT</span>;
      case 'txt':
        return <span className="badge badge-stock" style={{ fontSize: '10px', borderRadius: '4px', background: 'rgba(59,130,246,0.1)', color: '#3b82f6', border: '1px solid rgba(59,130,246,0.2)', padding: '2px 6px' }}>TXT</span>;
      case 'key':
        return <span className="badge badge-danger" style={{ fontSize: '10px', borderRadius: '4px', background: 'rgba(239,68,68,0.1)', color: '#ef4444', border: '1px solid rgba(239,68,68,0.2)', padding: '2px 6px' }}>KEY</span>;
      default:
        return <span className="badge" style={{ fontSize: '10px', borderRadius: '4px', padding: '2px 6px' }}>FILE</span>;
    }
  };

  return (
    <div className="compiler-container" style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '24px', alignItems: 'start' }}>
      {/* SECCIÓN IZQUIERDA: CARGADOR & VISOR */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
        
        {/* PANEL DE SUBIDA */}
        <div className="panel" style={{ marginBottom: 0 }}>
          <div className="panel-header">
            <div className="panel-title" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <UploadCloud size={16} style={{ color: 'var(--primary-color)' }} />
              Subir Archivo al Servidor TFTP
            </div>
          </div>

          <div 
            onDragEnter={handleDrag}
            onDragOver={handleDrag}
            onDragLeave={handleDrag}
            onDrop={handleDrop}
            onClick={() => fileInputRef.current?.click()}
            style={{
              border: `2px dashed ${dragActive ? 'var(--primary-color)' : 'var(--border-color)'}`,
              background: dragActive ? 'rgba(0,180,216, 0.05)' : 'rgba(255,255,255,0.01)',
              borderRadius: '8px',
              padding: '32px 24px',
              textAlign: 'center',
              cursor: 'pointer',
              transition: 'all 0.2s ease',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: '12px'
            }}
          >
            <input 
              ref={fileInputRef}
              type="file" 
              onChange={handleFileChange} 
              accept=".bin,.bat,.txt,.key"
              style={{ display: 'none' }} 
            />
            <div style={{
              background: 'rgba(0,180,216, 0.1)',
              color: 'var(--primary-color)',
              padding: '12px',
              borderRadius: '50%',
              display: 'flex',
              justifyContent: 'center',
              alignItems: 'center'
            }}>
              <UploadCloud size={24} />
            </div>
            <div>
              <p style={{ margin: 0, fontSize: '14px', fontWeight: '500', color: 'var(--text-color)' }}>
                {uploading ? 'Subiendo archivo al servidor...' : 'Arrastra o selecciona un archivo'}
              </p>
              <p style={{ margin: '4px 0 0 0', fontSize: '11px', color: 'var(--text-muted)' }}>
                Formatos permitidos: .bin (compilados), .bat (scripts), .txt (planos), .key (firmas)
              </p>
            </div>
          </div>
        </div>

        {/* VISOR DE ARCHIVO SELECCIONADO */}
        <div className="panel" style={{ marginBottom: 0, flexGrow: 1 }}>
          <div className="panel-header">
            <div className="panel-title" style={{ display: 'flex', alignItems: 'center', gap: '8px', width: '100%', justifyContent: 'space-between' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <FileText size={16} style={{ color: 'var(--primary-color)' }} />
                <span>Visor de Contenido</span>
              </div>
              {selectedFileName && getFileBadge(selectedFileName)}
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', minHeight: '300px' }}>
            {selectedFileName ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', flexGrow: 1 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '12px', borderBottom: '1px solid var(--border-color)', paddingBottom: '8px' }}>
                  <span style={{ fontWeight: 600, color: 'var(--text-color)' }}>Archivo activo: <code>{selectedFileName}</code></span>
                  <button 
                    className="btn" 
                    style={{ padding: '2px 8px', fontSize: '11px', borderRadius: '4px' }}
                    onClick={() => { setSelectedFileName(null); setSelectedFileNameContent(null); }}
                  >
                    Cerrar visor
                  </button>
                </div>
                
                {loadingContent ? (
                  <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', flexGrow: 1, height: '240px', opacity: 0.5 }}>
                    <div style={{ fontSize: '13px' }}>Cargando contenido del archivo...</div>
                  </div>
                ) : (
                  <textarea
                    readOnly
                    className="editor-textarea"
                    value={selectedFileContent || ''}
                    style={{ 
                      flexGrow: 1, 
                      minHeight: '240px', 
                      background: 'rgba(0,0,0,0.15)', 
                      fontFamily: 'monospace', 
                      fontSize: '12px', 
                      padding: '12px', 
                      borderRadius: '6px', 
                      border: '1px solid var(--border-color)', 
                      color: 'var(--text-color)', 
                      resize: 'vertical',
                      outline: 'none'
                    }}
                  />
                )}
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', flexGrow: 1, height: '300px', opacity: 0.5, border: '1px dashed var(--border-color)', borderRadius: '6px', padding: '24px', background: 'rgba(0,0,0,0.02)' }}>
                <File size={32} style={{ color: 'var(--text-muted)', marginBottom: '12px' }} />
                <p style={{ margin: 0, fontSize: '13px', textAlign: 'center', color: 'var(--text-color)' }}>Ningún archivo seleccionado</p>
                <p style={{ margin: '4px 0 0 0', fontSize: '11px', textAlign: 'center', color: 'var(--text-muted)' }}>Haz clic en un archivo .txt, .bat o .key en el directorio para visualizar su contenido aquí.</p>
              </div>
            )}
          </div>
        </div>

      </div>

      {/* SECCIÓN DERECHA: DIRECTORIO TFTP */}
      <div className="panel" style={{ marginBottom: 0, minHeight: '520px' }}>
        <div className="panel-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div className="panel-title" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Database size={16} style={{ color: 'var(--primary-color)' }} />
            Directorio TFTP (/tftpboot)
          </div>
          <button className="btn" style={{ padding: '4px 10px', fontSize: '11px' }} onClick={fetchFiles}>Actualizar</button>
        </div>

        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '400px', opacity: 0.5 }}>
            <div style={{ fontSize: '13px' }}>Cargando directorio de archivos...</div>
          </div>
        ) : files.length === 0 ? (
          <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', height: '400px', opacity: 0.5 }}>
            <File size={32} style={{ color: 'var(--text-muted)', marginBottom: '12px' }} />
            <p style={{ margin: 0, fontSize: '13px' }}>No hay archivos en el directorio.</p>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', maxHeight: '520px', overflowY: 'auto', paddingRight: '4px' }}>
            {files.map((file) => {
              const isSelected = selectedFileName === file.name;
              return (
                <div 
                  key={file.name} 
                  onClick={() => handleViewContent(file)}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    padding: '10px 14px',
                    borderRadius: '6px',
                    background: isSelected ? 'rgba(0,180,216, 0.08)' : 'rgba(255,255,255,0.02)',
                    border: `1px solid ${isSelected ? 'var(--primary-color)' : 'rgba(255,255,255,0.05)'}`,
                    cursor: 'pointer',
                    transition: 'all 0.15s ease',
                  }}
                  className="file-item-hover"
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px', minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', color: isSelected ? 'var(--primary-color)' : 'var(--text-muted)' }}>
                      <FileText size={16} />
                    </div>
                    <div style={{ minWidth: 0, textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap' }}>
                      <div style={{ fontWeight: 500, fontSize: '13px', color: 'var(--text-color)' }}>{file.name}</div>
                      <div style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '2px' }}>
                        Modificado: {new Date(file.lastModified).toLocaleDateString()}
                      </div>
                    </div>
                  </div>
                  
                  <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                      {getFileBadge(file.name)}
                      <span style={{ fontSize: '10px', color: 'var(--text-muted)', fontWeight: 500 }}>
                        {(file.size / 1024).toFixed(2)} KB
                      </span>
                    </div>

                    <button
                      onClick={(e) => handleDelete(e, file.name)}
                      style={{
                        background: 'none',
                        border: 'none',
                        color: 'var(--text-muted)',
                        cursor: 'pointer',
                        padding: '4px',
                        display: 'flex',
                        alignItems: 'center',
                        transition: 'color 0.2s',
                      }}
                      onMouseEnter={(e) => { e.currentTarget.style.color = '#ef4444'; }}
                      onMouseLeave={(e) => { e.currentTarget.style.color = 'var(--text-muted)'; }}
                      title="Eliminar del servidor"
                    >
                      <Trash2 size={13} />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};

export default BootfilesView;
