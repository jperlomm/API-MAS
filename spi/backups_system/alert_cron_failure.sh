#!/usr/bin/env bash
# =========================================================================
# SPI V1.6 - SCRIPT SRE DE ALERTA DE FALLA EN EJECUCIÓN DE CRON
# =========================================================================
set -Eeuo pipefail

# Importar utilidad de Telegram (Sabe consultar a Postgres si .env está vacío)
source /opt/backups_system/telegram.sh

# Enviar mensaje crítico
ERROR_MSG="🔴 *[ALERTA CRÍTICA SRE]* El programador (Cron) de tu contenedor de backups falló al ejecutar el script diario \`backup_and_verify.sh\`.

⚠️ *Detalle*: El script de respaldos no pudo iniciar o abortó de forma abrupta antes de registrar su propio log.
🛠️ *Acción requerida*: Revise los permisos de ejecución del archivo con \`chmod +x ~/spi/backups_system/*.sh\` o audite con \`docker logs isp-backup-manager\`."

send_telegram "$ERROR_MSG"
