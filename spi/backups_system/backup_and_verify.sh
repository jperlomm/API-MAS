#!/usr/bin/env bash
# =========================================================================
# SPI V1.6 - SCRIPT MAESTRO DE RESPALDOS CON ADICIÓN DE ALERTAS NOC
# =========================================================================

# Ajustes de robustez de Bash
set -Eeuo pipefail

# Importar utilidad de Telegram
# En el contenedor, la carpeta de scripts está mapeada en /opt/backups_system/
source /opt/backups_system/telegram.sh

# Variables del entorno (V1.7 Dinámicas desde Base de Datos)
get_db_config_backup() {
    local key="$1"
    if [ -n "${POSTGRES_PASSWORD:-}" ]; then
        PGPASSWORD="${POSTGRES_PASSWORD}" psql -h 127.0.0.1 -U postgres -d "${POSTGRES_DB:-dhcp}" -t -A -c "SELECT valor FROM admin.configuraciones WHERE clave = '${key}';" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

DATE_STR="$(date +%F)"
BACKUP_DIR="/opt/backups"
SQL_BACKUP="${BACKUP_DIR}/dhcp_prod_${DATE_STR}.sql"
TAR_BACKUP="${BACKUP_DIR}/spi_config_${DATE_STR}.tar.gz"

# Resolver retención y réplica de forma dinámica si no están en el entorno (V1.7)
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-}"
if [ -z "${BACKUP_RETENTION_DAYS}" ] || [ "${BACKUP_RETENTION_DAYS}" = "7" ]; then
    DB_VAL=$(get_db_config_backup 'backup_retention_days')
    BACKUP_RETENTION_DAYS="${DB_VAL:-7}"
fi

BACKUP_REMOTE_HOST="${BACKUP_REMOTE_HOST:-}"
if [ -z "${BACKUP_REMOTE_HOST}" ] || [ "${BACKUP_REMOTE_HOST}" = "192.168.2.X" ]; then
    DB_VAL=$(get_db_config_backup 'backup_remote_host')
    BACKUP_REMOTE_HOST="${DB_VAL:-192.168.2.X}"
fi

BACKUP_REMOTE_USER="${BACKUP_REMOTE_USER:-}"
if [ -z "${BACKUP_REMOTE_USER}" ] || [ "${BACKUP_REMOTE_USER}" = "usuario" ]; then
    DB_VAL=$(get_db_config_backup 'backup_remote_user')
    BACKUP_REMOTE_USER="${DB_VAL:-usuario}"
fi

BACKUP_REMOTE_PATH="${BACKUP_REMOTE_PATH:-}"
if [ -z "${BACKUP_REMOTE_PATH}" ] || [ "${BACKUP_REMOTE_PATH}" = "/home/usuario/backups_spi" ]; then
    DB_VAL=$(get_db_config_backup 'backup_remote_path')
    BACKUP_REMOTE_PATH="${DB_VAL:-/home/usuario/backups_spi}"
fi

# Definir un manejador de salida para capturar cualquier error inesperado de inmediato (EXIT TRAP)
on_exit() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        local error_msg="🔴 *[ALERTA CRÍTICA]* Falló el respaldo diario de producción del ISP.

⚠️ *Detalle*: El proceso de resguardo o la verificación SRE falló inesperadamente (código de salida: \`${exit_code}\`).
🛠️ *Acción requerida*: Revise los logs del contenedor con \`docker logs isp-backup-manager\` de inmediato para auditar el problema."
        send_telegram "$error_msg"
    fi
}
trap on_exit EXIT

echo "========================================================================="
echo "📅 [$(date '+%F %T')] INICIANDO CICLO DIARIO DE RESPALDO Y VERIFICACIÓN SRE"
echo "========================================================================="

# -------------------------------------------------------------------------
# PASO 1: RESPALDO DE BASE DE DATOS POSTGRES (DUMP)
# -------------------------------------------------------------------------
echo "📥 Paso 1: Generando dump de base de datos activa '${POSTGRES_DB}'..."

if ! docker exec -i isp-postgres pg_dump -U postgres -d "${POSTGRES_DB}" > "$SQL_BACKUP"; then
    echo "❌ ERROR CRÍTICO: El comando pg_dump falló."
    exit 1
fi

# Validar que el archivo exista y no esté vacío
if [ ! -f "$SQL_BACKUP" ] || [ ! -s "$SQL_BACKUP" ]; then
    echo "❌ ERROR CRÍTICO: El archivo de backup .sql está vacío o no se creó."
    exit 1
fi

SQL_SIZE=$(du -sh "$SQL_BACKUP" | cut -f1)
echo "✅ Paso 1 completado con éxito: ${SQL_SIZE}"

# -------------------------------------------------------------------------
# PASO 2: RESPALDO DE CONFIGURACIONES Y BOOTFILES (TAR)
# -------------------------------------------------------------------------
echo "📦 Paso 2: Comprimiendo configuraciones de la carpeta del proyecto..."

# Empaquetamos excluyendo los datos físicos voluminosos de la BD, otros backups y carpetas temporales
if ! tar --exclude='./postgres_data' \
         --exclude='./backups' \
         --exclude='./backups_system/data' \
         --exclude='./.git' \
         -czf "$TAR_BACKUP" -C /app/project .; then
    echo "❌ ERROR CRÍTICO: El comando tar para comprimir la configuración falló."
    exit 1
fi

TAR_SIZE=$(du -sh "$TAR_BACKUP" | cut -f1)
echo "✅ Paso 2 completado con éxito: ${TAR_SIZE}"

# -------------------------------------------------------------------------
# PASO 3: AUDITORÍA DE RESTAURACIÓN SRE (VERIFICACIÓN ACTIVA)
# -------------------------------------------------------------------------
echo "🚀 Paso 3: Iniciando prueba de restauración activa (SRE Audit)..."

TEMP_VERIFIER="postgres-backup-verifier"
VERIFIER_PASS="sre_verify_pass_123"

# Asegurar limpieza previa de contenedor de pruebas si quedó colgado por algún motivo
docker rm -f $TEMP_VERIFIER >/dev/null 2>&1 || true

# Levantar un postgres de prueba temporal en el host
docker run --name $TEMP_VERIFIER -e POSTGRES_PASSWORD=$VERIFIER_PASS -d postgres:alpine >/dev/null

echo "⏳ Esperando a que el motor de pruebas inicialice..."
sleep 6

# Intentar inyectar el backup de producción recién creado
echo "📥 Inyectando dump en el motor de pruebas..."
if ! docker exec -i $TEMP_VERIFIER psql -U postgres -d postgres < "$SQL_BACKUP" >/dev/null 2>&1; then
    echo "❌ ERROR DE INTEGRIDAD: El motor de base de datos de pruebas rechazó el archivo SQL."
    docker rm -f $TEMP_VERIFIER >/dev/null 2>&1 || true
    exit 1
fi

# Hacer un conteo real sobre la tabla de clientes comerciales
echo "📊 Validando coherencia de los datos comerciales recuperados..."
CLIENT_COUNT=$(docker exec -i $TEMP_VERIFIER psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM admin.clientes;" 2>/dev/null | xargs || echo "ERROR")

# Eliminar el contenedor temporal
docker rm -f $TEMP_VERIFIER >/dev/null 2>&1 || true

# Comprobar resultado del conteo
if [ "$CLIENT_COUNT" = "ERROR" ] || [ -z "$CLIENT_COUNT" ] || [ "$CLIENT_COUNT" -eq 0 ]; then
    echo "❌ ERROR CRÍTICO DE RESTAURACIÓN: El backup fue restaurado, pero no contiene registros de clientes válidos o está vacío."
    exit 1
fi

echo "✅ Paso 3 completado: El backup es 100% íntegro y restaurable."
echo "   -> Registro SRE: Se validó la existencia de ${CLIENT_COUNT} clientes comerciales en el entorno de pruebas."

# -------------------------------------------------------------------------
# PASO 4: REPLICACIÓN EN EL SEGUNDO SERVIDOR LOCAL (SCP)
# -------------------------------------------------------------------------
REPLICA_STATUS="Desactivada"
# El script valida si las variables fueron configuradas y no son los placeholders de ejemplo
if [ -n "${BACKUP_REMOTE_HOST}" ] && \
   [[ "${BACKUP_REMOTE_HOST}" != *"192.168.2.X"* ]] && \
   [ -n "${BACKUP_REMOTE_USER}" ]; then

    echo "📡 Paso 4: Replicando backups al segundo servidor local (${BACKUP_REMOTE_HOST})..."
    
    # Crear carpeta remota por si no existe
    ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa "${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}" "mkdir -p ${BACKUP_REMOTE_PATH}" || true

    # Transferir Dump SQL y Config Tar
    if scp -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa "$SQL_BACKUP" "$TAR_BACKUP" "${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}:${BACKUP_REMOTE_PATH}/"; then
        echo "✅ Replicación SCP completada exitosamente."
        REPLICA_STATUS="Exitosa en ${BACKUP_REMOTE_HOST}"
        
        # Purgado remoto de backups viejos en el servidor de réplica
        echo "🧹 Ejecutando rotación remota de backups antiguos en el servidor secundario..."
        ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa "${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}" \
            "find ${BACKUP_REMOTE_PATH} -type f \( -name 'dhcp_prod_*' -o -name 'spi_config_*' \) -mtime +${BACKUP_RETENTION_DAYS} -delete" || echo "⚠️ Advertencia: No se pudo limpiar la réplica remota."
    else
        echo "⚠️ ADVERTENCIA: No se pudo transferir el backup al servidor secundario. Comprueba conectividad."
        REPLICA_STATUS="Fallida (Error de red/SCP)"
    fi
else
    echo "📡 Paso 4: Replicación remota desactivada (no se configuraron variables ni SSH en .env)."
fi

# -------------------------------------------------------------------------
# PASO 5: ROTACIÓN LOCAL DE BACKUPS (LIMPIEZA DE ARCHIVOS EXPIRADOS)
# -------------------------------------------------------------------------
echo "🧹 Paso 5: Ejecutando rotación local de backups antiguos (> ${BACKUP_RETENTION_DAYS} días)..."

# Buscar y borrar backups locales que excedan el límite de retención
find "$BACKUP_DIR" -type f \( -name "dhcp_prod_*" -o -name "spi_config_*" \) -mtime "+${BACKUP_RETENTION_DAYS}" -delete

echo "✅ Paso 5 completado. Almacenamiento local purgado de archivos expirados."
echo "========================================================================="
echo "🎉 [$(date '+%F %T')] ¡PROCESO DE BACKUP FINALIZADO CON ÉXITO ABSOLUTO!"
echo "========================================================================="

# Al finalizar con éxito absoluto, enviar un resumen diario de estado por Telegram
success_msg="🟢 *[NOC]* Respaldo Diario Completado y Verificado

📅 *Fecha*: \`${DATE_STR}\`
📥 *Base de Datos*: \`dhcp\` (${SQL_SIZE})
📦 *Configuraciones*: \`spi_config\` (${TAR_SIZE})
📊 *SRE Auditoría*: **100% OK** (Se recuperaron ${CLIENT_COUNT} clientes en el entorno de pruebas)
📡 *Réplica*: \`${REPLICA_STATUS}\`
🧹 *Rotación*: Almacenamiento local purgado (> ${BACKUP_RETENTION_DAYS} días)"

send_telegram "$success_msg"
