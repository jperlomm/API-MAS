#!/bin/bash
# =============================================================================
# SPI MAS - PROXMOX HYPERVISOR PROVISIONING SCRIPT (IaC)
# =============================================================================
# Este script se ejecuta en la consola de tu servidor Proxmox físico (como root).
# Clona la plantilla, configura la red y contraseña, crea y adjunta los discos
# segmentados (SCSI1 y SCSI2) y enciende la VM automáticamente.
# =============================================================================

# Salir si ocurre un error
set -Eeuo pipefail

# Colores para la consola
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parámetros recibidos
VM_ID="${1:-}"
VM_IP="${2:-}"       # Formato: 192.168.2.106/24
VM_GW="${3:-}"       # Formato: 192.168.2.1
VM_PASS="${4:-}"     # Contraseña para el usuario 'usuario'

# Validar parámetros
if [ -z "$VM_ID" ] || [ -z "$VM_IP" ] || [ -z "$VM_GW" ] || [ -z "$VM_PASS" ]; then
    echo -e "${RED}❌ ERROR: Faltan parámetros obligatorios.${NC}"
    echo -e "Uso: $0 <VM_ID> <IP/SUBNET> <GATEWAY> <CONTRASEÑA>"
    echo -e "Ejemplo: $0 150 \"192.168.2.106/24\" \"192.168.2.1\" \"mi_clave_123\""
    exit 1
fi

TEMPLATE_ID="9000"
STORAGE_POOL="local-lvm"
VM_NAME="spi-prod-vm"

echo -e "${CYAN}=========================================================================${NC}"
echo -e "${CYAN}🤖 PROXMOX: PROVISIONAMIENTO AUTOMÁTICO DE VM PARA SPI MAS (ID $VM_ID)${NC}"
echo -e "${CYAN}=========================================================================${NC}"

# 1. Verificar si la plantilla existe
if ! qm status "$TEMPLATE_ID" >/dev/null 2>&1; then
    echo -e "${RED}❌ ERROR: No se encontró la plantilla VM ID $TEMPLATE_ID en Proxmox.${NC}"
    echo -e "Por favor, crea primero la plantilla siguiendo el PASO 1 de la GUIA_PROXMOX_CLOUD_INIT.md.${NC}"
    exit 1
fi

# 2. Clonar la plantilla en caliente (Full Clone)
echo -e "\n${YELLOW}📦 1/4 Clonando plantilla $TEMPLATE_ID hacia la nueva VM $VM_ID ($VM_NAME)...${NC}"
qm clone "$TEMPLATE_ID" "$VM_ID" --name "$VM_NAME" --full

# 3. Configurar Cloud-Init (IP, Gateway, Usuario y Contraseña)
echo -e "\n${YELLOW}🔧 2/4 Configurando Cloud-Init de red y contraseñas...${NC}"
qm set "$VM_ID" \
  --cipassword "$VM_PASS" \
  --ipconfig0 "ip=${VM_IP},gw=${VM_GW}"

# 4. Crear e insertar discos virtuales SCSI adicionales
echo -e "\n${YELLOW}💾 3/4 Creando y adjuntando discos segmentados independientes...${NC}"
echo -e "${CYAN}⚡ Creando disco SCSI1 de 40 GB para Motores Docker y base de datos...${NC}"
qm set "$VM_ID" --scsi1 "${STORAGE_POOL}:40,discard=on,ssd=1"

echo -e "${CYAN}📁 Creando disco SCSI2 de 20 GB para backups de resguardo...${NC}"
qm set "$VM_ID" --scsi2 "${STORAGE_POOL}:20,discard=on,ssd=1"

# 5. Encender la nueva VM de producción
echo -e "\n${YELLOW}🔌 4/4 Encendiendo la nueva VM $VM_ID...${NC}"
qm start "$VM_ID"

echo -e "\n${GREEN}=========================================================================${NC}"
echo -e "${GREEN}🎉 ¡PROVISIONAMIENTO EN PROXMOX INICIADO CON ÉXITO!${NC}"
echo -e "${GREEN}=========================================================================${NC}"
echo -e "La máquina virtual ID $VM_ID ya está encendida."
echo -e "Espera de 2 a 3 minutos a que Cloud-Init instale Docker, configure"
echo -e "los montajes y levante el sistema."
echo -e "Luego, inicia sesión con:"
echo -e "  ssh usuario@${VM_IP%%/*}"
echo -e "=========================================================================${NC}"
