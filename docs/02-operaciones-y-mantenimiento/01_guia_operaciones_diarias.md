# 🕵️‍♂️ SPI MAS: GUÍA DE OPERACIONES Y ADMINISTRACIÓN DE SISTEMAS
---
Esta guía contiene manuales rápidos y comandos esenciales para administrar, operar y mantener el sistema **SPI MAS** en producción (servidor Proxmox) y en tu entorno de desarrollo local.

---

## 🐋 1. COMANDOS ESENCIALES DE DOCKER

Todos estos comandos deben ejecutarse desde el servidor remoto en la carpeta del proyecto (`~/spi`), donde vive el archivo `docker-compose.yml`.

### ▶️ Encender y Apagar el Sistema
* **Encender todo en segundo plano (Recomendado):**
  ```bash
  docker compose up -d
  ```
* **Detener todos los servicios (sin borrar datos):**
  ```bash
  docker compose stop
  ```
* **Apagar y destruir contenedores (mantiene la base de datos intacta):**
  ```bash
  docker compose down
  ```

> [!CAUTION]
> **NUNCA utilices el comando `docker compose down -v`** en producción. La opción `-v` borra físicamente los volúmenes de datos asociados, lo que eliminaría de forma irreversible tu base de datos física PostgreSQL.

---

### 🔄 Reinicios y Reconstrucción en Caliente
* **Reiniciar un contenedor específico rápidamente (ej. DHCP):**
  ```bash
  docker compose restart kea-dhcp
  ```
* **Compilar y actualizar un servicio específico que modificaste (ej. API):**
  ```bash
  docker compose build admin-api
  docker compose up -d admin-api
  ```

---

### 📋 Monitoreo y Diagnóstico (Logs)
* **Ver logs en tiempo real de todo el sistema:**
  ```bash
  docker compose logs -f
  ```
* **Ver logs de un contenedor específico (últimas 50 líneas y seguir en vivo):**
  ```bash
  docker logs -f --tail 50 isp-admin-api
  ```
  *(Reemplaza `isp-admin-api` por `isp-kea-dhcp`, `isp-postgres`, o `isp-backup-manager` según desees).*

---

### 🧹 Mantenimiento de Disco (Liberar Espacio)
Con el tiempo, las imágenes Docker obsoletas consumen espacio. Para eliminarlas de forma segura sin tocar los datos activos de producción:
```bash
docker system prune -f
```

---

## 📂 2. MAPA DE ARCHIVOS CLAVE Y SU FUNCIÓN

### 🔧 En tu Servidor de Producción (`~/spi/`)
* **`~/spi/.env`**: Contiene las contraseñas reales de PostgreSQL, claves del bot de Telegram, rangos de red y la comunidad SNMP (`public`). **Este archivo no se sobreescribe con el deploy ni se sube a GitHub.**
* **`~/spi/docker-compose.yml`**: Orquestador de contenedores. Define cómo se interconectan la base de datos, la API, la Web, Kea DHCP, ToD, TFTP y el Backup Manager.
* **`~/spi/kea/kea-dhcp4.conf`**: Configuración estructural del servidor DHCP Kea (base de datos de leases, tiempos de renovación, subredes fijas).
* **`~/spi/backups_system/backup_and_verify.sh`**: Script SRE que corre a las 03:00 AM para resguardar la base de datos activa y probar su restauración automática en caliente.

### 💻 En tu Computadora Local de Desarrollo (`~/Documentos/antigravity/SPI-V1/`)
* **`deploy.sh`**: Tu script automatizado de despliegue en un clic.
* **`postgres_migration_complete.sql`**: Script de migración masiva/dinámica desde la base de datos legacy a PostgreSQL.
* **`spi/web/src/views/`**: Carpeta que contiene las pantallas de la interfaz web en React (ej: `SuscripcionesView.tsx`, `ClientesView.tsx`).
* **`spi/api/Controllers/`**: Carpeta con los controladores en C# de la API (ej: `ServiciosController.cs` que maneja suspensiones y reinicios SNMP).

---

## 🚀 3. FLUJO DE ACTUALIZACIÓN A PRODUCCIÓN (DEPLOY)

Cada vez que hagas un cambio de código local (en React o C#) y lo pruebes en tu computadora, envíalo al servidor de producción usando tu script automático:

### ⚡ Desplegar todo el proyecto (API + Web):
```bash
cd ~/Documentos/antigravity/SPI-V1
./deploy.sh
```

### ⚡ Desplegar únicamente cambios de la API (Backend C#):
```bash
./deploy.sh api
```

### ⚡ Desplegar únicamente cambios de la Web (Frontend React):
```bash
./deploy.sh web
```

---

## 🐙 4. COMANDOS CLAVE DE VERSIÓN Y RESPALDO (GIT / GITHUB)

Este flujo guarda tu historial de desarrollo en la nube de forma segura. Se ejecuta **siempre desde tu computadora local**.

### 🔍 1. Revisar qué archivos modificaste
Muestra los archivos editados que aún no se han confirmado o guardado:
```bash
git status
```

### 💾 2. Guardar tus cambios localmente
Prepara todos los archivos modificados respetando las exclusiones y crea un "punto de guardado" histórico:
```bash
git add .
git commit -m "Escribe aquí un resumen del cambio (ej: Agregada validación de MAC)"
```

### ☁️ 3. Subir tus cambios a GitHub
Sube tu historial de commits a la nube:
```bash
git push
```

### 📥 4. Descargar cambios de la nube (si trabajas en otra PC)
Sincroniza tu copia local con lo último que esté subido a GitHub:
```bash
git pull
```

---

## 📚 ÍNDICE MAESTRO DE MANUALES Y DOCUMENTACIÓN SRE (ARQUITECTURA DRY)

### 📂 01. Infraestructura y Servidores
* 📄 [01. Manual de Proxmox VE + Cloud-Init (IaC)](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/01-infraestructura-y-servidores/01_manual_proxmox_cloudinit.md)
* 📄 [02. Plantilla Cloud-Init User-Data YAML](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/01-infraestructura-y-servidores/02_plantilla_cloudinit_userdata.yaml)
* 📄 [03. Script de Aprovisionamiento Proxmox (`create_spi_server.sh`)](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/01-infraestructura-y-servidores/03_script_creacion_proxmox.sh)
* 📄 [04. Plantilla Debian Preseed CFG](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/01-infraestructura-y-servidores/04_plantilla_debian_preseed.cfg)

### 📂 02. Operaciones y Mantenimiento
* 📄 [01. Guía de Operaciones Diarias y Administración](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/02-operaciones-y-mantenimiento/01_guia_operaciones_diarias.md)
* 📄 [02. Actualización y Reparación de Servicios en Caliente (`--no-deps`)](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/02-operaciones-y-mantenimiento/02_actualizacion_y_reparacion_servicios.md)
* 📄 [03. Configuración y Autenticación SSH/Git en Servidor](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/02-operaciones-y-mantenimiento/03_configuracion_git_en_servidor.md)
* 📄 [04. Playbook de Recuperación ante Desastres (Disaster Recovery en Servidor Nuevo)](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/02-operaciones-y-mantenimiento/04_recuperacion_desastres_servidor_nuevo.md)

### 📂 03. Desarrollo e Integraciones
* 📄 [01. Documentación de API y Controladores](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/03-desarrollo-e-integraciones/01_documentacion_api.md)
* 📄 [02. Integración IPAM y Kea DHCP](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/03-desarrollo-e-integraciones/02_integracion_ipam_kea.md)
* 📄 [03. Manual de Migración de Base de Datos Legacy](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/03-desarrollo-e-integraciones/03_migracion_base_datos_legacy.md)

