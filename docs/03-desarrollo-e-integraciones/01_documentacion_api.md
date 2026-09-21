# 📖 Guía de Integración del API del SPI (SMI)

Bienvenido a la documentación de integración de la API del **Sistema de Aprovisionamiento e Infraestructura (SPI)**. Esta API permite a sistemas de terceros (CRMs, ERPs de facturación o scripts automatizados de monitoreo) gestionar abonados, dar de alta servicios técnicos de internet y consultar información de red en tiempo real.

La API corre por defecto en el puerto **`5152`** (o el configurado en tu entorno):
*   **Base URL:** `http://localhost:5152` o `http://<IP_API>:5152`

---

## 📌 Tabla de Contenidos
1. [Endpoints de Clientes (Abonados)](#1-endpoints-de-clientes-abonados)
2. [Endpoints de Servicios (Suscripciones e IPAM)](#2-endpoints-de-servicios-suscripciones-e-ipam)
3. [Endpoints de Equipamientos (Módems/ONUs)](#3-endpoints-de-equipamientos-módems-onus)
4. [Manejo de Respuestas y Códigos de Error](#4-manejo-de-respuestas-y-códigos-de-error)

---

## 1. Endpoints de Clientes (Abonados)

Gestión de la entidad comercial del cliente. Es obligatorio que un cliente exista para asignarle servicios.

### A. Crear Cliente
Crea una ficha de cliente en el sistema.
*   **Método:** `POST`
*   **Ruta:** `/api/clientes`
*   **Cuerpo de la Petición (`application/json`):**
    ```json
    {
      "razonSocial": "Distribuidora Mayorista S.A.",
      "cuitDni": "30712345678",
      "telefono": "1144332211",
      "email": "it@distribuidora.com",
      "calle": "Avenida Belgrano",
      "altura": "1200",
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
      "direccion": "Avenida Belgrano 1200, Ciudad Autónoma de Buenos Aires, Argentina"
    }
    ```

### B. Listar Clientes
Obtiene el listado completo de clientes.
*   **Método:** `GET`
*   **Ruta:** `/api/clientes`
*   **Respuesta Exitosa (`200 OK`):** Retorna un array con todos los clientes.

### C. Búsqueda de Clientes Permisiva (Fuzzy Search)
Busca clientes aplicando coincidencia parcial insensible a mayúsculas sobre su nombre, código, dirección fiscal, dirección de instalación de sus servicios, MACs asignadas o IPs activas.
*   **Método:** `GET`
*   **Ruta:** `/api/clientes/search?query=<termino_busqueda>`
*   **Ejemplo:** `GET /api/clientes/search?query=307123` (Busca por fragmento de CUIT)
*   **Respuesta Exitosa (`200 OK`):** Retorna un array con las fichas de clientes coincidentes (sin duplicados).

---

## 2. Endpoints de Servicios (Suscripciones e IPAM)

Los servicios representan la conexión física activa de un abonado. Vinculan un cliente, un equipo físico (MAC), un CMTS de cabecera y un plan de velocidad (paquete).

### A. Crear/Aprovisionar Servicio (Alta Técnica)
Realiza el alta de red de un servicio. Genera la IP del Cablemódem (`ip_cm`) de forma dinámica y permite elegir IP fija para el CPE o asignación `"AUTO"` por el motor IPAM. Además, genera la reserva en Kea DHCP.
*   **Método:** `POST`
*   **Ruta:** `/api/servicios`
*   **Cuerpo de la Petición (`application/json`):**
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
    > [!TIP]
    > Si se pasa `"AUTO"` en `ipCpe`, el motor IPAM seleccionará la siguiente IP estática disponible en las subredes CPE asignadas a ese CMTS.

*   **Respuesta Exitosa (`200 OK`):**
    ```json
    {
      "servicioId": 45,
      "ipCm": "10.20.100.5",
      "ipCpe": "172.18.110.15",
      "mensaje": "Servicio aprovisionado exitosamente en base de datos y servidor DHCP."
    }
    ```

### B. Consulta Unificada (Lookup de un Servicio)
Consulta un único servicio activo buscando de manera exacta por **Dirección MAC** o por **Código de Facturación**. Admite proyección dinámica de campos para reducir el ancho de banda transferido.
*   **Método:** `GET`
*   **Ruta:** `/api/servicios/lookup?mac=<mac>&codigo=<codigo>&fields=<bloques_separados_por_coma>`
*   **Ejemplo:** `GET /api/servicios/lookup?mac=aa:bb:cc:dd:ee:ff&fields=cliente,ips`
*   **Respuesta Exitosa (`200 OK`):**
    ```json
    {
      "servicioId": 45,
      "estado": "ACTIVO",
      "fechaActivacion": "2026-08-27T16:14:08",
      "cliente": {
        "id": 14,
        "codigoFacturacion": "ABO-50493",
        "razonSocial": "Distribuidora Mayorista S.A.",
        "cuitDni": "30712345678",
        "telefono": "1144332211",
        "email": "it@distribuidora.com",
        "direccionFiscal": "Avenida Belgrano 1200"
      },
      "ips": {
        "ipCm": "10.20.100.5",
        "ipCpe": "172.18.110.15",
        "esIpFija": true
      }
    }
    ```

### C. Búsqueda Permisiva de Servicios
Busca todos los servicios activos aplicando filtros cruzados por coincidencia parcial (coincide con nombre, calle de instalación, MAC o IPs). Soporta proyección dinámica de campos.
*   **Método:** `GET`
*   **Ruta:** `/api/servicios/search?query=<termino>&fields=<bloques>`
*   **Campos de Selección (`fields`):** `cliente`, `instalacion`, `equipamiento`, `ips`, `plan`.

---

## 3. Endpoints de Equipamientos (Módems/ONUs)

Gestión física de los equipos del almacén técnico.

### A. Registrar Equipo en Inventario
*   **Método:** `POST`
*   **Ruta:** `/api/equipos`
*   **Cuerpo de la Petición (`application/json`):**
    ```json
    {
      "mac": "AA:BB:CC:DD:EE:FF",
      "idModelo": 2,
      "estado": "INVENTARIO",
      "observaciones": "Equipo nuevo ingresado de depósito."
    }
    ```

---

## 4. Manejo de Respuestas y Códigos de Error

Toda petición fallida retornará un código HTTP de error (400, 404, 500) y un cuerpo JSON con el mensaje descriptivo del fallo bajo el atributo `error` o `message`.

### Ejemplo de Error de Transacción Abortada (`400 Bad Request`):
```json
{
  "error": "Transacción abortada: No hay direcciones IP estáticas libres disponibles en los pools reservados para este CMTS."
}
```

### Tabla de Códigos de Estado Comunes:
| Código | Descripción | Razón típica |
| :--- | :--- | :--- |
| **`200 OK`** | Operación exitosa | Retorno de datos o actualización de registros correcta. |
| **`201 Created`** | Creación exitosa | Se creó un recurso comercial o técnico (Cliente / Equipo). |
| **`400 Bad Request`** | Parámetros inválidos o error de lógica | El equipo no está en stock, formato de MAC inválido, IPs duplicadas o falta de pools libres. |
| **`404 Not Found`** | Recurso no encontrado | El abonado, MAC o código provistos no existen en el sistema. |
| **`500 Internal Error`** | Fallo del servidor | Pérdida de conexión con Postgres o Kea DHCP. |
