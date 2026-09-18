#!/usr/bin/env bash
# =========================================================================
# SPI V1.6 - TELEGRAM NOC WATCHDOG CON FILTRO DE RUIDO (SRE LIGHTWEIGHT)
# =========================================================================

# Ajustes de robustez
set -Eeuo pipefail

# Importar utilidad de Telegram
# En el contenedor, la carpeta de scripts está mapeada en /opt/backups_system/
source /opt/backups_system/telegram.sh

STATE_FILE="/tmp/alerted_containers.txt"
touch "$STATE_FILE"

echo "========================================================================="
echo "🕵️ [$(date '+%F %T')] INICIANDO TELEGRAM NOC WATCHDOG V1.6"
echo "========================================================================="

# Función para filtrar los contenedores críticos definidos de mutuo acuerdo
is_critical() {
    local name="$1"
    if [[ "$name" == "isp-postgres" || "$name" == "isp-kea-dhcp" || "$name" == "isp-admin-api" || "$name" == "isp-web-client" || "$name" == "isp-tftp" || "$name" == "isp-tod" ]]; then
        return 0
    fi
    return 1
}

# Funciones de control de estado en memoria para filtrar el ruido de reinicios
is_alerted() {
    local name="$1"
    [ -f "$STATE_FILE" ] && grep -qxF "$name" "$STATE_FILE"
}

add_alerted() {
    local name="$1"
    if ! is_alerted "$name"; then
        echo "$name" >> "$STATE_FILE"
    fi
}

remove_alerted() {
    local name="$1"
    if [ -f "$STATE_FILE" ]; then
        sed -i "/^${name}$/d" "$STATE_FILE"
    fi
}

# Notificación silenciosa de inicio del Watchdog
send_telegram "🕵️ *[NOC Watchdog]* Iniciado correctamente en producción. Monitoreando contenedores críticos con filtro de ruido activo."

# Escucha continua y reactiva de eventos del socket de Docker
docker events --filter 'event=die' --filter 'event=health_status' --format '{{.Actor.Attributes.name}} {{.Action}}' | while read -r name action; do
    [ -z "$name" ] && continue
    
    # Ignorar contenedores que no sean críticos
    if ! is_critical "$name"; then
        continue
    fi
    
    timestamp="$(date '+%F %T')"
    
    case "$action" in
        "die")
            # El contenedor crítico se detuvo de forma inesperada (proceso caído)
            message="🔴 *ISP ALERT*

*Servicio*: \`${name}\`
*Evento*: \`CONTAINER STOPPED\`
*Hora*: \`${timestamp}\`

El contenedor se ha caído inesperadamente. Docker intentará levantarlo según su política de reinicios."
            
            send_telegram "$message"
            add_alerted "$name"
            ;;
            
        "health_status: unhealthy")
            # El contenedor sigue ejecutándose pero su healthcheck interno falló las reintentos
            message="🔴 *ISP ALERT*

*Servicio*: \`${name}\`
*Evento*: \`UNHEALTHY\`
*Hora*: \`${timestamp}\`

El proceso está vivo pero el servicio interno está fallando o se encuentra congelado."
            
            send_telegram "$message"
            add_alerted "$name"
            ;;
            
        "health_status: healthy")
            # El contenedor vuelve a estar saludable. 
            # FILTRO DE RUIDO: Solo notificar si previamente se emitió una alerta
            if is_alerted "$name"; then
                message="🟢 *ISP RECOVERY*

*Servicio*: \`${name}\`
*Estado*: \`HEALTHY\`
*Hora*: \`${timestamp}\`

El servicio se ha recuperado y responde de manera óptima."
                
                send_telegram "$message"
                remove_alerted "$name"
            fi
            ;;
    esac
done
