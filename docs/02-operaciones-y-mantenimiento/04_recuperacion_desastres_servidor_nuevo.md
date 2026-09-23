# 🚨 PLAYBOOK SRE: RECUPERACIÓN ANTE DESASTRES (DISASTER RECOVERY EN SERVIDOR NUEVO)
---
Este manual contiene el procedimiento estándar de operaciones (SOP) para restaurar el sistema **SPI MAS** al 100% de su capacidad operativa en un **servidor o máquina virtual completamente nuevo** tras una falla total de hardware o desastre.

---

## 📋 PRERROQUISITOS
Antes de comenzar, debes contar con:
1. **Acceso a Proxmox VE** (o a un servidor Debian 12 limpio).
2. **El último archivo de respaldo de Base de Datos** (`dhcp_prod_YYYY-MM-DD.sql` o `spi40db.dump.gz`), obtenido de:
   - Disco de backups local (`/backups` en servidor secundario).
   - Notificaciones enviadas a Telegram por el NOC Watchdog.
   - Réplica remota por SCP/rsync.
3. **Clave SSH o credenciales de GitHub** para clonar el repositorio `jperlomm/API-MAS`.

---

## 🚀 PASO 1: APROVISIONAMIENTO DE LA NUEVA MÁQUINA VIRTUAL (2 MINUTOS)

Si estás utilizando **Proxmox VE**, ejecuta el script de aprovisionamiento automatizado directamente desde la consola del hipervisor físico (como `root`):

```bash
# Sintaxis: ./create_spi_server.sh <ID_VM> <IP/SUBNET> <GATEWAY> <CONTRASEÑA>
./create_spi_server.sh 150 "192.168.2.107/24" "192.168.2.13" "11Smme27"
```
*(Este script clonará la plantilla, redimensionará el disco raíz `scsi0` a 15 GB, adjuntará los discos de 40 GB para Docker y 20 GB para Backups, e instalará Docker automáticamente en 2 minutos).*

> 📄 **Detalles de la Infraestructura:** Para consultar la arquitectura de discos y plantillas, consulta el [Manual de Proxmox y Cloud-Init](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/01-infraestructura-y-servidores/01_manual_proxmox_cloudinit.md).

---

## 🚀 PASO 2: OBTENCIÓN DEL CÓDIGO FUENTE EN EL NUEVO SERVIDOR (1 MINUTO)

Tienes dos opciones sumamente sencillas para transferir todo el proyecto a la nueva máquina virtual:

### 🟢 Opción A: Usando `./deploy.sh` desde tu PC local de desarrollo (La más rápida y fácil)
Desde la terminal de tu computadora de desarrollo, simplemente ejecuta tu script de despliegue indicando la IP de la nueva VM:
```bash
cd ~/Documentos/antigravity/SPI-V1
./deploy.sh
```
*(Este comando utilizará `rsync` para copiar en 5 segundos todo el proyecto, scripts, docker-compose y compilaciones a la ruta `~/spi` del nuevo servidor sin requerir llaves SSH de GitHub).*

### 🔵 Opción B: Usando `git clone` directamente desde el servidor
Si estás conectado por SSH dentro del servidor y prefieres descargarlo desde GitHub:
```bash
ssh usuario@192.168.2.107
git clone git@github.com:jperlomm/API-MAS.git ~/spi
```

> 📄 **Autenticación con GitHub:** Si utilizas la Opción B y la nueva VM no tiene autorizada tu llave SSH en GitHub, sigue la [Guía de Configuración de Git en Servidor](file:///home/usuario/Documentos/antigravity/SPI-V1/docs/02-operaciones-y-mantenimiento/03_configuracion_git_en_servidor.md).

---

## 🔐 PASO 3: CONFIGURAR ARCHIVO DE VARIABLES DE ENTORNO (`.ENV`)

Navega a la carpeta del proyecto y crea el archivo `.env` con las credenciales del ISP:

```bash
cd ~/spi
nano .env
```

Pega el siguiente contenido ajustando las variables si es necesario:
```env
#########################################
# CONFIGURACIÓN GENERAL DEL ISP         #
#########################################
ISP_NAME=MMC
POSTGRES_PASSWORD=P0stgr3s
POSTGRES_DB=dhcp

SNMP_COMMUNITY=public

BACKUP_REMOTE_HOST=192.168.2.X
BACKUP_REMOTE_USER=usuario
BACKUP_REMOTE_PATH=/home/usuario/backups_spi
BACKUP_RETENTION_DAYS=7

TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
```
*(Nota: Si dejas `TELEGRAM_BOT_TOKEN` vacío, el sistema recuperará dinámicamente el token desde la base de datos de producción una vez restaurada).*

---

## 🐳 PASO 4: LEVANTAR LA PILA DE CONTENEDORES DOCKER (1 MINUTO)

Ejecuta Docker Compose para construir y poner en marcha los servicios:

```bash
cd ~/spi
docker compose up -d
```

Verifica que todos los contenedores estén corriendo de forma saludable:
```bash
docker compose ps
```
*(Verás activos los contenedores: `isp-postgres`, `isp-kea-dhcp`, `isp-backend`, `isp-frontend`, `isp-backup-manager` e `isp-tftp`).*

---

## 📥 PASO 5: RESTAURACIÓN DEL BACKUP DE BASE DE DATOS (30 SEGUNDOS)

Copia el archivo de respaldo `.sql` o `.dump.gz` al nuevo servidor (por SCP, pendrive o carpeta `~/spi/backups/`) e inyéctalo en el contenedor activo de PostgreSQL:

### Caso A: Si el backup es un archivo `.sql` plano (Ejemplo estándar de respaldo diario):
```bash
docker exec -i isp-postgres psql -U postgres -d dhcp < ~/spi/backups/dhcp_prod_2026-09-23.sql
```

### Caso B: Si el backup es un archivo comprimido `.sql.gz` o `.dump.gz`:
```bash
gunzip -c ~/spi/backups/spi40db.dump.gz | docker exec -i isp-postgres psql -U postgres -d dhcp
```

*(El proceso de inyección tardará entre 2 y 10 segundos según el tamaño del ISP).*

---

## 🔄 PASO 6: REINICIO Y VERIFICACIÓN SRE DE SALUD

1. Reinicia los servicios para que **Kea DHCP**, la **API Backend** y el **Backup Manager** carguen en memoria la base de datos restaurada:
   ```bash
   docker compose restart
   ```

2. **Ejecuta la prueba de auditoría SRE en caliente:**
   ```bash
   docker exec -it isp-backup-manager /bin/bash -c "/opt/backups_system/backup_and_verify.sh"
   ```

   **Resultado Esperado:**
   - ✅ Generación de dump limpia.
   - ✅ Verificación de coherencia comercial SRE (clientes y cablemodems recuperados).
   - ✅ Notificación verde recibida en Telegram con el reporte del ISP.

3. **Verifica las interfaces Web y API:**
   - Panel de Administración: `http://192.168.2.107`
   - Estado de la API: `http://192.168.2.107:8000/api/health`

---

## 🆘 CHECKLIST DE RESOLUCIÓN DE PROBLEMAS EN EMERGENCIA

| Síntoma | Causa Posible | Solución Rápida |
| :--- | :--- | :--- |
| `Permission denied` al ejecutar scripts | Falta permiso ejecutable en disco | Ejecutar `chmod +x ~/spi/backups_system/*.sh` |
| Kea DHCP no asigna IPs | Base de datos no fue reiniciada tras el restore | Ejecutar `docker compose restart kea-dhcp` |
| `Permission denied` en el Cron de Backups | Archivos sobrescritos tras `git pull` | Reiniciar el servicio con `docker compose restart backup-manager` |
| Base de datos sin espacio | Disco `/dev/sda1` no fue expandido | Ejecutar `sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1` |
