// =========================================================================
// INTERFACES Y CONTRATOS DE DATOS (TYPESCRIPT SCHEMAS)
// =========================================================================

export interface Pais {
  id?: number;
  nombre: string;
}

export interface Provincia {
  id?: number;
  nombre: string;
  idPais: number;
  pais?: string;
}

export interface Localidad {
  id?: number;
  nombre: string;
  idProvincia: number;
  provincia?: string;
  idPais?: number;
  pais?: string;
}

export interface Cliente {
  id?: number;
  razonSocial: string;
  cuitDni: string;
  telefono?: string | null;
  email?: string | null;
  calle?: string | null;
  altura?: string | null;
  idLocalidad?: number | null;
  localidad?: string | null;
  provincia?: string | null;
  pais?: string | null;
  codigo?: string | null;
  direccion?: string | null;
  latitud?: number | null;
  longitud?: number | null;
}

export interface Equipo {
  id?: number;
  idModelo: number;
  modelo?: string;
  tipoTecnologico?: string;
  mac: string;
  numeroSerie?: string | null;
  estado?: 'INVENTARIO' | 'ACTIVO' | 'SUSPENDIDO' | 'BAJA' | 'FALLADO';
  fechaAlta?: string;
}

export interface HardwareModelo {
  id?: number;
  idMarca: number;
  marca?: string;
  nombre: string;
  tipo: 'DOCSIS' | 'GPON';
  descripcion?: string | null;
}

export interface HardwareMarca {
  id: number;
  nombre: string;
}

export interface CMTS {
  id?: number;
  nombre: string;
  ipControl: string;
  comunidadSnmp?: string | null;
}

export interface Subred {
  id?: number;
  idCmts: number;
  cmts?: string;
  nombre: string;
  cidr: string;
  gateway: string;
  tipo?: string;
}

export interface Pool {
  id?: number;
  idSubred: number;
  subred?: string;
  rangoInicio: string;
  rangoFin: string;
  idPaquete?: number | null;
  clientClass?: string | null;
  totalIps?: number;
  ipsAsignadas?: number;
  esEstatico?: boolean;
}

export interface Paquete {
  id?: number;
  nombre: string;
  velocidadBajadaKbps: number;
  velocidadSubidaKbps: number;
  limiteDispositivos: number;
  bootfile?: string | null;
  dhcp4ClientClass?: string | null;
}

export interface Servicio {
  id?: number;
  idCliente: number;
  cliente?: string;
  idEquipo: number;
  equipoMac?: string;
  idPaquete: number;
  paquete?: string;
  ipAsignada?: string | null;
  idCmts?: number;
  cmts?: string;
  ipCm?: string | null;
  ipCpe?: string | null;
  estado?: 'ACTIVO' | 'SUSPENDIDO';
  fechaActivacion?: string;
  direccionInstalacion?: string | null;
}

export interface DhcpMonitorRates {
  discoverPerMin: number | null;
  requestPerMin: number | null;
  ackPerMin: number | null;
  nakPerMin: number | null;
  dropPerMin: number | null;
}

export interface DhcpMonitorRaw {
  discoverTotal: number | null;
  requestTotal: number | null;
  ackTotal: number | null;
  nakTotal: number | null;
  dropTotal: number | null;
}

export interface DhcpMonitor {
  keaAvailable: boolean;
  rates: DhcpMonitorRates | null;
  raw: DhcpMonitorRaw | null;
  ackRequestRatio: number | null;
}

export interface DhcpHistoryEntry {
  fecha: string;
  discovers: number;
  requests: number;
  acks: number;
  naks: number;
  drops: number;
}

export interface DashboardKpis {
  clientesTotal: number;
  equiposTotal: number;
  equiposStock: number;
  equiposActivos: number;
  serviciosActivos: number;
  serviciosSuspendidos: number;
  dhcpLoad5Min: number;
  dhcpMonitor?: DhcpMonitor;
}


export interface TftpFile {
  name: string;
  size: number;
  lastModified: string;
}

// =========================================================================
// SERVICIO CENTRALIZADO DE FETCH (CLIENTE API REST CON SEGURIDAD JWT)
// =========================================================================

export interface LoggedUser {
  id: string;
  username: string;
  nombreCompleto: string;
  email: string;
  rol: 'ADMIN' | 'OPERADOR' | 'TECNICO';
}

let accessTokenInMemory: string | null = null;
let isRefreshing = false;
let refreshSubscribers: ((token: string) => void)[] = [];

export function setAccessToken(token: string | null) {
  accessTokenInMemory = token;
}

export function getAccessToken(): string | null {
  return accessTokenInMemory;
}

const subscribeTokenRefresh = (callback: (token: string) => void) => {
  refreshSubscribers.push(callback);
};

const onRefreshed = (token: string) => {
  refreshSubscribers.forEach((cb) => cb(token));
  refreshSubscribers = [];
};

export async function apiFetch<T = any>(
  url: string,
  options?: RequestInit
): Promise<{ data?: T; error?: string; success: boolean }> {
  try {
    const config: RequestInit = {
      credentials: 'include', // REQUERIDO para enviar y recibir cookies HttpOnly de Refresh Token
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...(accessTokenInMemory ? { 'Authorization': `Bearer ${accessTokenInMemory}` } : {}),
        ...(options?.headers || {}),
      },
    };

    const response = await fetch(url, config);
    let data: any = null;

    const contentType = response.headers.get('content-type');
    if (contentType && contentType.includes('application/json')) {
      data = await response.json();
    } else {
      const text = await response.text();
      data = text ? { message: text } : null;
    }

    // INTERCEPTAR ERROR 401: Intento de Silent Refresh transparente ante Token Expirado
    if (response.status === 401 && !url.includes('/api/auth/login') && !url.includes('/api/auth/refresh')) {
      if (!isRefreshing) {
        isRefreshing = true;
        
        // Ejecutar petición única de refresco al Backend
        apiFetch<{ accessToken: string }>('/api/auth/refresh', { method: 'POST' })
          .then((res) => {
            isRefreshing = false;
            if (res.success && res.data?.accessToken) {
              setAccessToken(res.data.accessToken);
              onRefreshed(res.data.accessToken);
            } else {
              setAccessToken(null);
              // Despachar evento global para que el contexto de React fuerce el redirect al Login
              window.dispatchEvent(new Event('auth-logout'));
            }
          })
          .catch(() => {
            isRefreshing = false;
            setAccessToken(null);
            window.dispatchEvent(new Event('auth-logout'));
          });
      }

      // Devolver una nueva promesa que se resolverá cuando el refresh termine exitosamente
      return new Promise((resolve) => {
        subscribeTokenRefresh((token) => {
          const retryConfig = {
            ...config,
            headers: {
              ...config.headers,
              'Authorization': `Bearer ${token}`,
            },
          };
          resolve(apiFetch(url, retryConfig));
        });
      });
    }

    if (!response.ok) {
      let errorMessage = data?.error || data?.message || data?.detail || `Fallo en la operación (${response.status})`;
      if (data?.details) {
        errorMessage = `${errorMessage}\nDetalles:\n${data.details}`;
      }
      return {
        success: false,
        error: errorMessage,
      };
    }

    return {
      success: true,
      data: data as T,
    };
  } catch (error: any) {
    console.error('API Fetch Exception:', error);
    return {
      success: false,
      error: 'Error de red. No se pudo establecer conexión con el servidor API.',
    };
  }
}

export async function getDhcpHistory() {
  return apiFetch<DhcpHistoryEntry[]>('/api/dashboard/history');
}
