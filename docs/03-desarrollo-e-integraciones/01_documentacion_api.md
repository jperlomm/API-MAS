# 📖 Guía de Integración de la API de SPI MAS

Bienvenido a la documentación oficial de la API REST del **Sistema de Aprovisionamiento e Infraestructura (SPI MAS)**. Esta API permite a sistemas externos (CRMs, sistemas de facturación ERP, plataformas de autogestión o scripts de monitoreo NOC) gestionar abonados, realizar altas técnicas, modificar planes de velocidad, suspender/reactivar servicios por morosidad y auditar la red en tiempo real.

*   **Base URL:** `http://<IP_SERVIDOR>:5152`
*   **Formato de Intercambio:** `application/json`
*   **Autenticación:** JWT Bearer Token

---

## 📌 Tabla de Contenidos

1. [Autenticación y Seguridad](#1-autenticación-y-seguridad)
2. [Gestión Comercial de Clientes (Abonados)](#2-gestión-comercial-de-clientes-abonados)
3. [Gestión Técnica de Servicios (Suscripciones y Ciclo de Vida)](#3-gestión-técnica-de-servicios-suscripciones-y-ciclo-de-vida)
4. [Acciones de Suspensión, Reactivación y Operaciones Masivas](#4-acciones-de-suspensión-reactivación-y-operaciones-masivas)
5. [Gestión de Equipamientos de Inventario (Módems/ONUs)](#5-gestión-de-equipamientos-de-inventario-módemsonus)
6. [Topología de Red, IPAM y Planes Comerciales](#6-topología-de-red-ipam-y-planes-comerciales)
7. [Diagnósticos, Leases e Historiales SRE](#7-diagnósticos-leases-e-historiales-sre)
8. [Manejo de Errores y Códigos de Estado](#8-manejo-de-errores-y-códigos-de-estado)

---

## 1. Autenticación y Seguridad

Todas las peticiones a la API (excepto la ruta de login) requieren un token de acceso **JWT Bearer** en la cabecera HTTP `Authorization`.

### A. Iniciar Sesión (Obtener JWT)
*   **Método:** `POST`
*   **Ruta:** `/api/auth/login`
*   **Cuerpo de la Petición:**
    ```json
    {
      "username": "admin",
      "password": "TuPasswordSegura"
    }
    ```
*   **Respuesta Exitosa (`200 OK`):**
    ```json
    {
      "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      "username": "admin",
      "nombre": "Administrador General",
      "rol": "ADMIN"
    }
    ```

### B. Encabezado en Peticiones Posteriores
Incluye el token en cada llamada:
```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

---

## 2. Gestión Comercial de Clientes (Abonados)

Administra la ficha comercial del cliente. Es el titular responsable de uno o más servicios técnicos de internet.

### A. Listar Clientes
*   **Método:** `GET`
*   **Ruta:** `/api/clientes`
*   **Respuesta Exitosa (`200 OK`):** Retorna el listado completo de clientes.

### B. Obtener Ficha de Cliente por ID
*   **Método:** `GET`
*   **Ruta:** `/api/clientes/{id}`
*   **Respuesta Exitosa (`200 OK`):** Retorna la ficha detallada con sus servicios contratados.

### C. Búsqueda Permisiva de Clientes (Fuzzy Search)
Busca por CUIT/DNI, razón social, dirección fiscal, código de facturación, MAC de equipo o IP.
*   **Método:** `GET`
*   **Ruta:** `/api/clientes/search?query=<termino>`
*   **Ejemplo:** `GET /api/clientes/search?query=307123`

### D. Crear Cliente
*   **Método:** `POST`
*   **Ruta:** `/api/clientes`
*   **Cuerpo de la Petición:**
    ```json
    {
      "razonSocial": "Distribuidora Mayorista S.A.",
      "cuitDni": "30712345678",
      "telefono": "1144332211",
      "email": "it@distribuidora.com",
      "calle": "Avenida Belgrano",
      "altura": "1200",
      "pisoDepto": "Piso 3",
      "idLocalidad": 1,
      "codigo": "ABO-50493"
    }
    ```
*   **Respuesta Exitosa (`201 Created`):**
    ```json
    {
      "id": 14,
      "razonSocial": "Distribuidora Mayorista S.A.",
      "codigo": "ABO-50493",
      "direccion": "Avenida Belgrano 1200, Piso 3"
    }
    ```

### E. Modificar Cliente (Update)
*   **Método:** `PUT`
*   **Ruta:** `/api/clientes/{id}`
*   **Cuerpo de la Petición:** JSON con los campos actualizados (misma estructura que el POST).

### F. Borrar Cliente
Elimina la ficha comercial. Bloqueado si el abonado posee servicios activos.
*   **Método:** `DELETE`
*   **Ruta:** `/api/clientes/{id}`

---

## 3. Gestión Técnica de Servicios (Suscripciones y Ciclo de Vida)

Vincula un abonado, un equipo físico (MAC), un CMTS y un plan de velocidad en el servidor Kea DHCP.

### A. Listar Todos los Servicios
*   **Método:** `GET`
*   **Ruta:** `/api/servicios`

### B. Obtener Servicio por ID
*   **Método:** `GET`
*   **Ruta:** `/api/servicios/{id}`

### C. Lookup Exacto (por MAC o Código de Facturación)
*   **Método:** `GET`
*   **Ruta:** `/api/servicios/lookup?mac=<mac>&codigo=<codigo>&fields=<bloques>`
*   **Ejemplo:** `GET /api/servicios/lookup?mac=AA:BB:CC:DD:EE:FF&fields=cliente,ips`

### D. Búsqueda Permisiva de Servicios
*   **Método:** `GET`
*   **Ruta:** `/api/servicios/search?query=<termino>`

### E. Crear / Aprovisionar Servicio (Alta Técnica)
Realiza el aprovisionamiento de red. Genera las reservas en Kea DHCP y asigna IP según la estrategia seleccionada.
*   **Método:** `POST`
*   **Ruta:** `/api/servicios`
*   **Cuerpo de la Petición:**
    ```json
    {
      "idCliente": 14,
      "idEquipo": 34,
      "idPaquete": 3,
      "idCmts": 1,
      "ipCm": null,
      "ipCpe": "AUTO",
      "direccionInstalacion": "Av. de Mayo 456, Piso 2"
    }
    ```
    *   `ipCm`: `null` (dinámica por DHCP de gestión) o una IP fija dentro de la subred `CM`.
    *   `ipCpe`: `"AUTO"` (asigna automáticamente la siguiente IP fija disponible del pool), `null` (dinámica del plan) o una IP fija IPv4.

### F. Editar / Actualizar Servicio (Cambio de Plan o Equipo)
Permite modificar el plan de velocidad, cambiar la MAC asignada o la IP. Actualiza Kea DHCP en tiempo real y encola el reinicio SNMP del módem.
*   **Método:** `PUT`
*   **Ruta:** `/api/servicios/{id}`
*   **Cuerpo de la Petición:**
    ```json
    {
      "idCliente": 14,
      "idEquipo": 38,
      "idPaquete": 5,
      "idCmts": 1,
      "ipCm": null,
      "ipCpe": "AUTO",
      "direccionInstalacion": "Av. de Mayo 456, Piso 2"
    }
    ```

### G. Baja Completa de Servicio
Elimina la suscripción de la base de datos, remueve la reserva de Kea DHCP y devuelve el equipo a stock (`INVENTARIO`).
*   **Método:** `DELETE`
*   **Ruta:** `/api/servicios/{id}`

---

## 4. Acciones de Suspensión, Reactivación y Operaciones Masivas

Permite el corte y la reconexión de servicios técnicos por razones comerciales o administrativas.

### A. Suspender Servicio Individual (Falta de Pago)
Cambia el estado a `SUSPENDIDO`, remueve las reservas de navegación en Kea DHCP para aislar el equipo y encola el reinicio del módem.
*   **Método:** `POST` o `PUT`
*   **Ruta:** `/api/servicios/{id}/suspender`
*   **Respuesta Exitosa (`200 OK`):**
    ```json
    {
      "id": 45,
      "estado": "SUSPENDIDO",
      "message": "Suscripción suspendida. Las reservas en Kea DHCP han sido eliminadas automáticamente y se encoló el reinicio del módem."
    }
    ```

### B. Reactivar Servicio Individual (Rehabilitación)
Restablece el estado a `ACTIVO`, re-aprovisiona las reservas en Kea DHCP con su plan de velocidad y encola el reinicio SNMP.
*   **Método:** `POST` o `PUT`
*   **Ruta:** `/api/servicios/{id}/reactivar`
*   **Respuesta Exitosa (`200 OK`):**
    ```json
    {
      "id": 45,
      "estado": "ACTIVO",
      "message": "Suscripción reactivada con éxito. El Cablemódem y el CPE han sido re-aprovisionados en Kea DHCP."
    }
    ```

### C. Suspensión / Reactivación Masiva por Lista de IDs
Permite procesar múltiples servicios en un solo llamado optimizado en base de datos.
*   **Método:** `POST`
*   **Ruta:** `/api/servicios/bulk-estado`
*   **Cuerpo de la Petición:**
    ```json
    {
      "ids": [45, 46, 89, 102],
      "nuevoEstado": "SUSPENDIDO"
    }
    ```
*   **Respuesta Exitosa (`200 OK`):**
    ```json
    {
      "procesados": 4,
      "estadoAplicado": "SUSPENDIDO",
      "message": "Se actualizaron 4 suscripciones comerciales y se inyectaron en la cola de reinicios masivos seguros."
    }
    ```

### D. Suspensión / Reactivación Masiva por Código de Facturación
Ideal para integración con ERPs de cobranzas que envían listas de códigos de abonados morosos o regularizados.
*   **Método:** `POST`
*   **Ruta:** `/api/servicios/bulk-estado-by-codigos`
*   **Cuerpo de la Petición:**
    ```json
    {
      "codigos": ["ABO-1001", "ABO-1002", "ABO-1055"],
      "nuevoEstado": "ACTIVO"
    }
    ```

---

## 5. Gestión de Equipamientos de Inventario (Módems/ONUs)

### A. Listar Equipos
*   **Método:** `GET`
*   **Ruta:** `/api/equipos`

### B. Registrar Nuevo Equipo en Almacén
*   **Método:** `POST`
*   **Ruta:** `/api/equipos`
*   **Cuerpo de la Petición:**
    ```json
    {
      "mac": "AA:BB:CC:DD:EE:FF",
      "idModelo": 2,
      "estado": "INVENTARIO",
      "observaciones": "Ingreso de depósito central"
    }
    ```

### C. Modificar Equipo
*   **Método:** `PUT`
*   **Ruta:** `/api/equipos/{id}`

### D. Eliminar Equipo
*   **Método:** `DELETE`
*   **Ruta:** `/api/equipos/{id}`

---

## 6. Topología de Red, IPAM y Planes Comerciales

### A. Consultar Siguiente IP Libre (Engine IPAM)
Calcula y bloquea por 5 minutos la siguiente IP estática disponible en una subred.
*   **Método:** `GET`
*   **Ruta:** `/api/ipam/next-free-ip?idCmts=1&tipo=CPE&idPaquete=3`
*   **Respuesta Exitosa (`200 OK`):**
    ```json
    {
      "ip": "172.250.2.15"
    }
    ```

### B. CRUD de Nodos CMTS
*   `GET /api/red/cmts` - Listar nodos
*   `POST /api/red/cmts` - Registrar nodo CMTS
*   `PUT /api/red/cmts/{id}` - Modificar CMTS
*   `DELETE /api/red/cmts/{id}` - Eliminar CMTS

### C. CRUD de Subredes IP (Scopes)
*   `GET /api/red/subredes` - Listar subredes
*   `POST /api/red/subredes` - Asignar subred (`tipo`: `"CM"` o `"CPE"`)
*   `PUT /api/red/subredes/{id}` - Modificar subred
*   `DELETE /api/red/subredes/{id}` - Borrar subred

### D. CRUD de Pools DHCP (Rangos IPAM)
*   `GET /api/red/pools` - Listar pools y porcentaje de uso
*   `POST /api/red/pools` - Crear pool DHCP
*   `PUT /api/red/pools/{id}` - Modificar pool
*   `DELETE /api/red/pools/{id}` - Eliminar pool

### E. CRUD de Planes Comerciales (Paquetes de Velocidad)
*   `GET /api/red/paquetes` - Listar planes
*   `POST /api/red/paquetes` - Crear plan de velocidad (ej. 100M/10M)
*   `PUT /api/red/paquetes/{id}` - Modificar plan
*   `DELETE /api/red/paquetes/{id}` - Borrar plan

---

## 7. Diagnósticos, Leases e Historiales SRE

### A. Consultar Concesiones Activas Kea DHCP (Leases)
*   **Método:** `GET`
*   **Ruta:** `/api/diagnostics/leases`

### B. Consultar Reservas de Host Activas en Kea
*   **Método:** `GET`
*   **Ruta:** `/api/diagnostics/hosts`

### C. Consultar Historial de IPs por Abonado / MAC
*   **Método:** `GET`
*   **Ruta:** `/api/diagnostics/history/ip?query=<mac_o_ip>`

### D. Consultar Historial de Modificaciones de Equipos
*   **Método:** `GET`
*   **Ruta:** `/api/diagnostics/history/hardware?query=<mac_o_cliente>`

---

## 8. Manejo de Errores y Códigos de Estado

Toda respuesta fallida retorna un código de estado HTTP adecuado y un objeto JSON descriptivo con el motivo del fallo.

### Ejemplo de Error de Transacción Abortada (`400 Bad Request`):
```json
{
  "error": "Transacción de actualización abortada: La IP de ruteo CPE fija '172.250.2.200' no pertenece a ninguna subred 'CPE' habilitada en el CMTS asignado."
}
```

### Tabla de Códigos HTTP:
| Código | Descripción | Significado |
| :--- | :--- | :--- |
| **`200 OK`** | Exitoso | La operación se completó y los datos han sido retornados/procesados. |
| **`201 Created`** | Creado | Recurso comercial o técnico creado correctamente. |
| **`400 Bad Request`** | Error de Validación | Parámetros incorrectos, IP fuera de rango, MAC duplicada o falta de pools. |
| **`401 Unauthorized`** | No Autorizado | Token JWT inválido, expirado o ausente en el header. |
| **`404 Not Found`** | No Encontrado | El cliente, servicio, equipo o ID provisto no existe. |
| **`500 Internal Error`** | Error de Servidor | Fallo en la conexión con PostgreSQL o Kea DHCP. |
