# 🐋 DEPLOYMENT BLUEPRINT: PROXMOX VE + DEBIAN 12 CLOUD-INIT (MULTI-DISK)
---
Esta guía detalla la implementación paso a paso de la **Opción B**: una máquina virtual Debian 12 en Proxmox VE aprovisionada de forma 100% automatizada mediante **Cloud-Init** (utilizando el archivo `cloud_init_user_data.yaml` para instalar Docker) y segmentada con **múltiples discos virtuales independientes** para garantizar la seguridad, el aislamiento y el máximo rendimiento de la base de datos de producción.

---

## 🏗️ ARQUITECTURA FISICA Y LOGICA DE DISCOS

| Disco Proxmox | Dispositivo en VM | Tamaño Sugerido | Clase de Almacenamiento | Punto de Montaje | Propósito |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`scsi0`** | `/dev/sda` | `15 GB` | SSD / NVMe (Rápido) | `/` (Raíz) | Sistema operativo Debian 12 base. |
| **`scsi1`** | `/dev/sdb` | `40 GB`+ | SSD / NVMe (Muy Rápido) | `/var/lib/docker` | Base de datos PostgreSQL (`postgres_data`) y motores Docker. |
| **`scsi2`** | `/dev/sdc` | `20 GB`+ | HDD / NAS (Económico) | `/backups` | Almacenamiento aislado de backups `.sql` y `.tar.gz`. |

---

## 🛠️ PASO 1: DESCARGAR Y PREPARAR LA PLANTILLA EN PROXMOX VE (CLI)

Ejecuta estos comandos directamente desde la **consola SSH física de tu servidor Proxmox VE** (como usuario `root` de Proxmox) para descargar la imagen oficial de Debian y convertirla en una plantilla reutilizable.

### 1. Descargar la imagen de Debian Cloud-Init
```bash
cd /var/lib/vz/template/qemu/
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
```

### 2. Crear la máquina virtual base (ID de ejemplo: `9000`)
```bash
qm create 9000 \
  --name debian12-cloud-template \
  --memory 4096 \
  --cores 2 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single
```

### 3. Importar la imagen descargada al pool de almacenamiento de Proxmox (ej: `local-lvm`)
```bash
qm importdisk 9000 debian-12-generic-amd64.qcow2 local-lvm
```

### 4. Adjuntar el disco importado a la VM como `scsi0` y activar soporte SSD/Discard (TRIM)
```bash
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0,discard=on,ssd=1
```

### 5. Añadir la controladora virtual Cloud-Init
```bash
qm set 9000 --ide2 local-lvm:cloudinit
```

### 6. Configurar orden de arranque (Boot Order) para iniciar desde `scsi0`
```bash
qm set 9000 --boot order=scsi0
```

### 7. Configurar puerto serie para soporte de consola Proxmox (xterm.js)
```bash
qm set 9000 --serial0 socket --vga serial0
```

---

## 🚀 PASO 2: VINCULAR EL ARCHIVO CLOUD-INIT AUTOMATIZADO

Para que la máquina virtual instale automáticamente Docker y habilite el acceso por SSH con contraseña en su primer arranque, debemos vincular el archivo `cloud_init_user_data.yaml` que creamos:

1. **Subir el archivo de automatización a Proxmox:**
   Copia el contenido de tu archivo local `docs/cloud_init_user_data.yaml` y guárdalo en tu servidor Proxmox físico como un archivo en la ruta de fragmentos de código (*Snippets*):
   `/var/lib/vz/snippets/cloud_init_user_data.yaml`

2. **Asociar el archivo a la plantilla `9000`:**
   En la consola de tu servidor Proxmox, ejecuta el siguiente comando para registrar el script personalizado de inicio:
   ```bash
   qm set 9000 --cicustom "user=local:snippets/cloud_init_user_data.yaml"
   ```

3. **Convertir la VM en una Plantilla inmutable:**
   Ahora que la plantilla tiene la automatización de Docker y SSH vinculada, conviértela en plantilla:
   ```bash
   qm template 9000
   ```

---

## 👥 PASO 3: CLONACIÓN Y CONFIGURACIÓN GRÁFICA EN PROXMOX

Cada vez que necesites crear un nuevo servidor de producción (ej: tu máquina de producción ID `150` con nombre `spi-prod`):

1. Haz clic derecho sobre la plantilla `debian12-cloud-template` (`9000`) y selecciona **Clone**.
   * Modo: **Full Clone**.
   * ID: **150** (o el que desees).
   * Nombre: **spi-prod**.
2. Selecciona la nueva VM `150` y ve a la pestaña **Cloud-Init**:
   * **User:** `usuario`
   * **Password:** Escribe la contraseña de administrador que desees. (Proxmox la inyectará automáticamente en el sistema de forma segura).
   * **IP Config:** Configura tu IP estática real de producción (ej: `192.168.2.106/24` con gateway `192.168.2.1`).
   * Haz clic en el botón **Regenerate Image** para aplicar los cambios.

---

## 💾 PASO 4: CREAR Y ADJUNTAR LOS DISCOS SECUNDARIOS Y TERCIARIOS

Desde la sección de **Hardware** de la nueva VM clonada (`150`) en Proxmox, o mediante SSH en Proxmox VE, agregamos los discos adicionales físicos antes de iniciar la VM por primera vez.

```bash
# Agregar un disco SCSI1 de 40 GB para Docker (en almacenamiento rápido local-lvm)
qm set 150 --scsi1 local-lvm:40,discard=on,ssd=1

# Agregar un disco SCSI2 de 20 GB para Backups (en almacenamiento seguro)
qm set 150 --scsi2 local-lvm:20,discard=on,ssd=1
```

---

## 🏁 PASO 5: ARRANQUE, FORMATEO Y AUTOMONTAJE PERSISTENTE

1. Enciende la máquina virtual `150` desde la interfaz de Proxmox.
2. Espera unos **2 o 3 minutos** mientras el sistema se inicializa por primera vez. Cloud-Init se encargará en segundo plano de:
   * Crear el usuario, actualizar el SO y habilitar SSH por contraseña.
   * Instalar dependencias, descargar llaves GPG de Docker, agregar el repositorio e **instalar Docker Engine + Docker Compose v2 de forma nativa**.
   * Configurar los permisos de usuario del grupo `docker`.
3. Conéctate por SSH desde tu terminal utilizando tu contraseña:
   ```bash
   ssh usuario@192.168.2.106
   ```

Una vez dentro, formateamos y configuramos el montaje persistente para asegurar que los motores de Docker y Postgres escriban en las particiones correctas de alta velocidad:

### 1. Formatear las particiones con sistema de archivos `ext4`
```bash
# Formatear el disco SCSI1 (sdb) para Docker
sudo mkfs.ext4 -L docker_data /dev/sdb

# Formatear el disco SCSI2 (sdc) para Backups
sudo mkfs.ext4 -L backups_data /dev/sdc
```

### 2. Obtener los identificadores únicos (UUID) de los nuevos discos
```bash
sudo blkid
```
*Identifica las líneas correspondientes a `/dev/sdb` (LABEL="docker_data") y `/dev/sdc` (LABEL="backups_data") y copia sus valores UUID.*

### 3. Configurar el montaje persistente en `/etc/fstab`
Edita el archivo de sistemas de archivos:
```bash
sudo nano /etc/fstab
```
Agrega las siguientes dos líneas al final del archivo (reemplazando los UUID por tus UUID reales):

```fstab
# Disco SCSI1 dedicado para Docker y Base de Datos (en NVMe/SSD)
UUID=tu-uuid-de-sdb-aquí  /var/lib/docker  ext4  defaults,nofail,discard,noatime  0  2

# Disco SCSI2 dedicado para Respaldos SRE (en almacenamiento de resguardo)
UUID=tu-uuid-de-sdc-aquí  /backups         ext4  defaults,nofail,discard  0  2
```

### 4. Montar los discos y verificar
```bash
# Montar los discos en caliente sin reiniciar
sudo mount -a

# Verificar que quedaron montados en sus rutas respectivas
df -h
```
*Deberías ver `/dev/sdb` montado en `/var/lib/docker` y `/dev/sdc` montado en `/backups`.*

### 5. Reiniciar el servicio de Docker para que use el volumen de alta velocidad
```bash
sudo systemctl restart docker
```

¡Listo! Tu servidor está 100% aprovisionado de forma automatizada, con una arquitectura multi-disco virtual robusta y los motores de Docker activos y operando sobre SSDs rápidos.
