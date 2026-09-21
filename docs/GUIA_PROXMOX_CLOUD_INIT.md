# 🐋 DEPLOYMENT BLUEPRINT: PROXMOX VE + DEBIAN 12 CLOUD-INIT (MULTI-DISK)
---
Esta guía detalla la implementación paso a paso de la **Opción B**: una máquina virtual Debian 12 en Proxmox VE aprovisionada mediante **Cloud-Init** y segmentada con **múltiples discos virtuales independientes** para garantizar la seguridad, el aislamiento y el máximo rendimiento de entrada/salida (I/O) de la base de datos de producción.

---

## 🏗️ ARQUITECTURA FISICA Y LOGICA DE DISCOS (PROPUESTA)

| Disco Proxmox | Dispositivo en VM | Tamaño Sugerido | Clase de Almacenamiento | Punto de Montaje | Propósito |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`scsi0`** | `/dev/sda` | `15 GB` | SSD / NVMe (Rápido) | `/` (Raíz) | Sistema operativo Debian 12 base. |
| **`scsi1`** | `/dev/sdb` | `40 GB`+ | SSD / NVMe (Muy Rápido) | `/var/lib/docker` | Base de datos PostgreSQL (`postgres_data`) y motores Docker. |
| **`scsi2`** | `/dev/sdc` | `20 GB`+ | HDD / NAS (Económico) | `/backups` | Almacenamiento aislado de backups `.sql` y `.tar.gz`. |

---

## 🛠️ PASO 1: DESCARGAR Y CONFIGURAR LA PLANTILLA EN PROXMOX VE (CLI)

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

### 4. Adjuntar el disco importado a la VM como `scsi0` y activar soporte SSD/Discard
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

### 8. Convertir la VM en una Plantilla inmutable
```bash
qm template 9000
```

---

## 👥 PASO 2: CONFIGURACIÓN INICIAL EN LA INTERFAZ DE PROXMOX

Una vez creada la plantilla con ID `9000`, puedes clonarla para crear tu máquina virtual de producción real (ej: ID `150` con nombre `spi-prod`).

1. Haz clic derecho sobre la plantilla `debian12-cloud-template` y selecciona **Clone**.
   * Modo: **Full Clone**.
   * ID: **150** (o el que desees).
   * Nombre: **spi-prod**.
2. Ve a la VM `150` y haz clic en la pestaña **Cloud-Init**:
   * **User:** `usuario`
   * **Password:** Configura una contraseña robusta de administrador.
   * **SSH Keys:** Pega el contenido de tu clave pública SSH local (`id_rsa.pub` o `id_ed25519.pub`) para ingresar por SSH sin contraseña.
   * **IP Config:** Asigna una IP estática real en tu segmento de gestión (ej: `192.168.2.106/24` con gateway `192.168.2.1`).
   * Haz clic en **Regenerate Image** para guardar la configuración.

---

## 💾 PASO 3: CREAR Y ADJUNTAR LOS DISCOS SECUNDARIOS Y TERCIARIOS

Desde la sección de **Hardware** de la nueva VM clonada (`150`) en Proxmox, o mediante SSH en Proxmox VE, agregamos los discos adicionales para Docker y Backups.

```bash
# Agregar un disco SCSI1 de 40 GB para Docker (en almacenamiento rápido local-lvm)
qm set 150 --scsi1 local-lvm:40,discard=on,ssd=1

# Agregar un disco SCSI2 de 20 GB para Backups (puede ser en almacenamiento lvm-lento o local-lvm)
qm set 150 --scsi2 local-lvm:20,discard=on,ssd=1
```

---

## 🚀 PASO 4: FORMATEO Y MONTAJE AUTOMÁTICO EN LA VM DEBIAN (PRIMER ARRANQUE)

Inicia la máquina virtual `150` desde Proxmox. Ingresa por SSH desde tu computadora local:
```bash
ssh usuario@192.168.2.106
```

Una vez dentro de Debian, vamos a formatear y montar las particiones adicionales de forma segura en `/etc/fstab` para que se monten solas en cada arranque:

### 1. Formatear los discos con sistema de archivos `ext4` (ultra estable)
```bash
# Formatear el disco secundario (sdb -> scsi1) para Docker
sudo mkfs.ext4 -L docker_data /dev/sdb

# Formatear el disco terciario (sdc -> scsi2) para Backups
sudo mkfs.ext4 -L backups_data /dev/sdc
```

### 2. Crear las carpetas de montaje en el sistema de archivos
```bash
# Crear el directorio de backups de producción
sudo mkdir -p /backups

# Detener temporalmente Docker si estuviese instalado para liberar el directorio
sudo systemctl stop docker || true
sudo mkdir -p /var/lib/docker
```

### 3. Obtener los identificadores únicos (UUID) de los nuevos discos
Los UUID garantizan que los discos se monten de forma correcta aunque cambien de orden físico de conexión. Ejecuta:
```bash
sudo blkid
```
*Identifica las líneas que corresponden a `/dev/sdb` (LABEL="docker_data") y `/dev/sdc` (LABEL="backups_data") y copia sus UUID.*

### 4. Configurar el montaje automático en `/etc/fstab`
Edita el archivo de automontaje:
```bash
sudo nano /etc/fstab
```
Agrega las siguientes dos líneas al final del archivo (reemplazando los UUID de ejemplo por tus UUID reales obtenidos en el paso anterior):

```fstab
# Disco SCSI1 dedicado para Docker y Base de Datos (en NVMe/SSD)
UUID=tu-uuid-de-sdb-aquí  /var/lib/docker  ext4  defaults,nofail,discard,noatime  0  2

# Disco SCSI2 dedicado para Respaldos SRE (en almacenamiento seguro)
UUID=tu-uuid-de-sdc-aquí  /backups         ext4  defaults,nofail,discard  0  2
```

### 5. Probar y montar los discos sin reiniciar
```bash
sudo mount -a
```
*Verifica que los discos se montaron correctamente ejecutando el comando:*
```bash
df -h
```
*Debes ver `/dev/sdb` montado en `/var/lib/docker` y `/dev/sdc` montado en `/backups`.*

---

## 🐋 PASO 5: INSTALACIÓN AUTOMÁTICA DE DOCKER ENGINE

Ahora que el almacenamiento está perfectamente aislado, ejecuta este script rápido oficial para instalar Docker Engine directo en su partición de alta velocidad `/var/lib/docker`:

```bash
# 1. Instalar dependencias necesarias
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# 2. Agregar la clave GPG oficial de Docker
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 3. Configurar el repositorio de Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Instalar Docker y Docker Compose v2
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Dar permisos a tu usuario administrativo para correr docker sin 'sudo'
sudo usermod -aG docker usuario

# 6. Activar los cambios de grupo de usuario al instante
newgrp docker
```

¡Felicidades! Tienes un servidor Debian 12 bajo Proxmox con un almacenamiento de arquitectura multi-disco virtual impecable, Docker instalado en un volumen de alta velocidad y backups aislados de forma ultra-segura.
