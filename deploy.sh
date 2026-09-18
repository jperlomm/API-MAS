#!/bin/bash
# =============================================================================
# SPI MAS - SCRIPT DE DESPLIEGUE AUTOMATIZADO EN PRODUCCIÓN (DevOps CD)
# =============================================================================
# Uso:
#   ./deploy.sh          -> Sincroniza todo y actualiza AMBOS contenedores (api y web)
#   ./deploy.sh api      -> Sincroniza todo y actualiza solo el Backend (.NET API)
#   ./deploy.sh web      -> Sincroniza todo y actualiza solo el Frontend (React Nginx)
# =============================================================================

# Detener el script si ocurre algún error inesperado
set -Eeuo pipefail

# Configuración de Servidor de Producción (VM en Proxmox)
SERVER_USER="usuario"
SERVER_IP="192.168.2.106"
REMOTE_DIR="~/spi"

# Directorio local absoluto del proyecto (resuelve donde sea que se invoque el script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="${SCRIPT_DIR}/spi/"

# Códigos de color ANSI para la terminal
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # Sin Color (Reset)

# Servicio a actualizar (por defecto 'all')
SERVICE="${1:-all}"

echo -e "${CYAN}=========================================================================${NC}"
echo -e "${CYAN}🕵️‍♂️ SPI MAS: INICIANDO PIPELINE DE DESPLIEGUE AUTOMÁTICO HACIA EL SERVIDOR${NC}"
echo -e "${CYAN}=========================================================================${NC}"

# Paso 1: Sincronización de Archivos Segura con rsync
echo -e "\n${YELLOW}📥 Paso 1: Sincronizando código fuente local con el host remoto...${NC}"
rsync -avz --delete \
  --exclude='postgres_data/' \
  --exclude='backups/' \
  --exclude='node_modules/' \
  --exclude='bin/' \
  --exclude='obj/' \
  --exclude='.git/' \
  --exclude='*.env' \
  "$LOCAL_DIR" "$SERVER_USER@$SERVER_IP:$REMOTE_DIR/"

echo -e "${GREEN}✅ Paso 1 completado: Servidor sincronizado con el código más reciente.${NC}"

# Paso 2: Recompilación y Despliegue del Contenedor de Producción
echo -e "\n${YELLOW}🚀 Paso 2: Reconstruyendo imágenes y levantando servicios en Docker...${NC}"

if [ "$SERVICE" = "all" ]; then
    echo -e "${CYAN}🤖 Procesando AMBOS servicios en caliente: web-client y admin-api...${NC}"
    ssh "$SERVER_USER@$SERVER_IP" "cd $REMOTE_DIR && docker compose build web-client admin-api && docker compose up -d web-client admin-api"
elif [ "$SERVICE" = "api" ]; then
    echo -e "${CYAN}⚡ Procesando únicamente el Backend: admin-api...${NC}"
    ssh "$SERVER_USER@$SERVER_IP" "cd $REMOTE_DIR && docker compose build admin-api && docker compose up -d admin-api"
elif [ "$SERVICE" = "web" ]; then
    echo -e "${CYAN}🌐 Procesando únicamente el Frontend: web-client...${NC}"
    ssh "$SERVER_USER@$SERVER_IP" "cd $REMOTE_DIR && docker compose build web-client && docker compose up -d web-client"
else
    echo -e "${RED}❌ ERROR: El parámetro '$SERVICE' no es válido.${NC}"
    echo -e "Uso del script: ./deploy.sh [all | api | web]"
    exit 1
fi

echo -e "\n${GREEN}=========================================================================${NC}"
echo -e "${GREEN}🎉 ¡DESPLIEGUE FINALIZADO Y OPERATIVO EN CALIENTE CON ÉXITO ABSOLUTO!${NC}"
echo -e "${GREEN}=========================================================================${NC}"
