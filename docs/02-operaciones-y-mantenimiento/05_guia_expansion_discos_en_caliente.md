# 💽 Guía de Expansión de Discos en Caliente (Sin Reiniciar la VM)

En entornos de producción con alta demanda, la base de datos de PostgreSQL, el registro de Docker o el almacén de backups pueden requerir mayor almacenamiento. Esta guía detalla cómo **redimensionar y expandir en caliente** cualquier disco de la máquina virtual **sin apagar el servidor ni interrumpir los servicios del ISP**.

---

## 🏗️ Arquitectura de Discos de la VM en Proxmox

| Disco Virtual | Punto de Montaje | Tamaño Inicial | Dispositivo Linux | Propósito Principal |
| :--- | :--- | :--- | :--- | :--- |
| **`scsi0`** | `/` (Raíz) | `15 GB` | `/dev/sda1` | Sistema Operativo Debian 12 |
| **`scsi1`** | `/var/lib/docker` | `40 GB` | `/dev/sdb` | Motor Docker y Base de Datos `spi_postgres_data` |
| **`scsi2`** | `/backups` | `20 GB` | `/dev/sdc` | Resguardos `.sql` y configuraciones diarias |

---

## ⚡ PASO 1: Agrandar el Disco desde Proxmox

Puedes realizar la expansión del disco virtual desde la interfaz web de Proxmox o mediante la consola de comandos de Proxmox (Node Shell).

### Opción A: Desde la Interfaz Web de Proxmox (GUI)
1. Selecciona la VM del sistema SPI en el panel izquierdo de Proxmox.
2. Ve a la pestaña **Hardware**.
3. Selecciona el disco que deseas expandir (`Hard Disk (scsi0)`, `Hard Disk (scsi1)` o `Hard Disk (scsi2)`).
4. Haz clic en el botón superior **Disk Action** -> **Resize**.
5. Ingresa el tamaño adicional a agregar en GB (Ejemplo: `10` para agregar 10 GB más).
6. Haz clic en **Resize disk**.

### Opción B: Desde la Consola de Proxmox (CLI)
Ejecuta en el nodo de Proxmox reemplazando `<VM_ID>` por el número de tu máquina virtual (ejemplo: `100`):

```bash
# Para agrandar el Disco Raíz / (scsi0) en +10 GB:
qm resize <VM_ID> scsi0 +10G

# Para agrandar el Disco de Docker / Base de Datos (scsi1) en +20 GB:
qm resize <VM_ID> scsi1 +20G

# Para agrandar el Disco de Backups (scsi2) en +20 GB:
qm resize <VM_ID> scsi2 +20G
```

---

## 🐧 PASO 2: Expandir el Sistema de Archivos en Linux (En Caliente)

Conéctate por SSH a la máquina virtual Debian del ISP y ejecuta los comandos correspondientes al disco que acabas de redimensionar. **No se requiere reiniciar la VM.**

---

### 🟢 Caso 1: Expansión del Disco Raíz `/` (`scsi0` -> `/dev/sda1`)

```bash
# 1. Expandir la partición 1 del disco sda:
sudo growpart /dev/sda 1

# 2. Redimensionar el sistema de archivos ext4 en caliente:
sudo resize2fs /dev/sda1
```

---

### 🔵 Caso 2: Expansión del Disco de Docker y Base de Datos (`scsi1` -> `/dev/sdb`)

*(Dado que el disco secundario no usa tabla de particiones y está formateado directamente en `ext4`, la expansión del sistema de archivos es instantánea e inline)*:

```bash
# Redimensionar el volumen de Docker / Postgres en caliente:
sudo resize2fs /dev/sdb
```

---

### 🟡 Caso 3: Expansión del Disco de Backups (`scsi2` -> `/dev/sdc`)

```bash
# Redimensionar el almacén de respaldos en caliente:
sudo resize2fs /dev/sdc
```

---

## ✅ PASO 3: Verificación SRE de Almacenamiento

Comprueba que el espacio adicional ya esté disponible para el sistema operativo y Docker:

```bash
df -h / /var/lib/docker /backups
```

*(Verás reflejado de inmediato el nuevo tamaño total y el espacio disponible sin que los contenedores de Docker hayan dejado de funcionar en ningún momento).*
