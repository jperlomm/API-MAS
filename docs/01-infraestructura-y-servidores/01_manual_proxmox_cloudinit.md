# 🐋 DEPLOYMENT BLUEPRINT: PROXMOX VE + DEBIAN 12 CLOUD-INIT (100% AUTOMATIZADO)
---
Esta guía detalla el aprovisionamiento de infraestructura como código (IaC) de **SPI MAS**: una máquina virtual Debian 12 en Proxmox VE con **múltiples discos virtuales independientes** y motores de Docker listos, todo automatizado mediante scripts para reducir tu trabajo manual a **literalmente un solo comando**.

---

## 🏗️ ARQUITECTURA FISICA Y LOGICA DE DISCOS

| Disco Proxmox | Dispositivo en VM | Tamaño Sugerido | Clase de Almacenamiento | Punto de Montaje | Propósito |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`scsi0`** | `/dev/sda` | `15 GB` | SSD / NVMe (Rápido) | `/` (Raíz) | Sistema operativo Debian 12 base. |
| **`scsi1`** | `/dev/sdb` | `40 GB`+ | SSD / NVMe (Muy Rápido) | `/var/lib/docker` | Base de datos PostgreSQL (`postgres_data`) y motores Docker. |
| **`scsi2`** | `/dev/sdc` | `20 GB`+ | HDD / NAS (Económico) | `/backups` | Almacenamiento aislado de backups `.sql` y `.tar.gz`. |

---

## 🛠️ PASO 1: CREAR LA PLANTILLA BASE EN EL PROXMOX FISICO (CLI)

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

## 🚀 PASO 2: VINCULAR LA AUTOMATIZACIÓN DE CLOUD-INIT

Para que todas las VMs que clones instalen automáticamente Docker, habiliten SSH con contraseña, formateen y monten las particiones adicionales en el primer arranque, asociamos nuestro archivo `02_plantilla_cloudinit_userdata.yaml`:

1. **Subir el archivo de automatización a Proxmox:**
   Copia el contenido de tu archivo local `docs/01-infraestructura-y-servidores/02_plantilla_cloudinit_userdata.yaml` y guárdalo en tu servidor Proxmox físico en la ruta de fragmentos de código (*Snippets*):
   `/var/lib/vz/snippets/cloud_init_user_data.yaml`

2. **Asociar el archivo a la plantilla `9000`:**
   En la consola de tu servidor Proxmox, ejecuta el siguiente comando para registrar el script personalizado de inicio:
   ```bash
   qm set 9000 --cicustom "user=local:snippets/cloud_init_user_data.yaml"
   ```

3. **Convertir la VM en una Plantilla inmutable:**
   ```bash
   qm template 9000
   ```

---

## 🤖 PASO 3: CREAR NUEVOS SERVIDORES CON UN SOLO COMANDO (PROXMOX CLI)

Hemos automatizado toda la clonación, configuración de IP, contraseñas y asignación de discos a través del script **`03_script_creacion_proxmox.sh`**. 

1. Copia el archivo `docs/01-infraestructura-y-servidores/03_script_creacion_proxmox.sh` a tu servidor Proxmox físico como `/root/create_spi_server.sh`.

touch create_spi_server.sh
nano create_spi_server.sh

2. Dale permisos de ejecución:
   ```bash
   chmod +x /root/create_spi_server.sh
   ```
3. **Ejecuta el script para aprovisionar un servidor entero en 1 segundo:**
   ```bash
   # Sintaxis: ./create_spi_server.sh <ID_DE_VM> <IP/SUBNET> <GATEWAY> <CONTRASEÑA>
   ./create_spi_server.sh 150 "192.168.2.107/24" "192.168.2.13" "11Smme27"
   ```

El script se encargará de clonar la plantilla, inyectar la red/contraseña, crear y adjuntar los discos SCSI1 (40GB) y SCSI2 (20GB), y arrancar la máquina virtual de inmediato.

---

## 🛠️ MANTENIMIENTO: REDIMENSIONAR DISCOS EN VMs EXISTENTES
Si tienes una VM previa (por ejemplo, la VM 150) cuyo disco base `scsi0` figuraba con 3 GB en Proxmox:

1. **En la consola SSH de Proxmox física (root):**
   ```bash
   qm resize 150 scsi0 +12G
   ```
2. **Dentro de la VM Debian por SSH (`ssh usuario@192.168.2.107`):**
   ```bash
   sudo growpart /dev/sda 1
   sudo resize2fs /dev/sda1
   ```
   *(Esto expandirá en caliente el sistema de archivos `/dev/sda1` a 15 GB con más de 11 GB libres de inmediato).*

---

## 🏁 PASO 4: INGRESAR Y DESPLEGAR EL SISTEMA (CERO TRABAJO MANUAL)

1. Enciende la VM (el script lo hace por ti) y **espera de 2 a 3 minutos** en tu pantalla sin tocar nada.
2. En ese primer booteo, **la VM Debian se auto-configurará de forma silenciosa**:
   * Redimensionará automáticamente el disco principal `/dev/sda1` de 3 GB a **15 GB**.
   * Formateará los discos secundarios SCSI1 y SCSI2 en `ext4`.
   * Los montará de forma persistente en `/var/lib/docker` y `/backups` y escribirá las entradas correspondientes en `/etc/fstab`.
   * Agregará las llaves GPG, repositorios oficiales e **instalará Docker Engine + Docker Compose v2 directamente sobre el almacenamiento rápido**.
   * Configurará tu cuenta de SSH y los permisos del grupo `docker`.
3. Conéctate directamente por SSH usando la contraseña que definiste:
   ```bash
   ssh usuario@192.168.2.107
   ```
4. **Verifica que los discos estén listos, extendidos y montados:**
   ```bash
   df -h
   ```
   *(Verás `/dev/sda1` con 15 GB, `/dev/sdb` montado en `/var/lib/docker` y `/dev/sdc` montado en `/backups`)*.

5. **¡Listo! Despliega SPI MAS con Volumen Nombrado:**
   Solo te queda clonar tu código de producción en el servidor y levantar tus contenedores Docker con un comando:
   ```bash
   cd ~/spi && docker compose up -d
   ```
   *(La base de datos utilizará el volumen nombrado `spi_postgres_data` almacenado físicamente en el disco de 40 GB `/var/lib/docker`)*.

¡Felicidades! Tienes un sistema de aprovisionamiento automatizado e Infraestructura como Código (IaC) digno de una arquitectura corporativa moderna.
