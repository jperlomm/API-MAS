#!/usr/bin/env bash

# Obtener configuración desde la base de datos PostgreSQL si no está en el entorno (V1.7)
get_db_config() {
    local key="$1"
    if [ -n "${POSTGRES_PASSWORD:-}" ]; then
        PGPASSWORD="${POSTGRES_PASSWORD}" psql -h 127.0.0.1 -U postgres -d "${POSTGRES_DB:-dhcp}" -t -A -c "SELECT valor FROM admin.configuraciones WHERE clave = '${key}';" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Utilidad de envío de mensajes de Telegram
send_telegram() {
    local mensaje="$1"
    
    # Resolver credenciales dinámicamente si no están provistas por variable de entorno (V1.7)
    local bot_token="${TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${TELEGRAM_CHAT_ID:-}"
    
    if [ -z "${bot_token}" ]; then
        bot_token=$(get_db_config 'telegram_bot_token')
    fi
    if [ -z "${chat_id}" ]; then
        chat_id=$(get_db_config 'telegram_chat_id')
    fi

    if [ -n "${bot_token}" ] && [ -n "${chat_id}" ]; then
        local response
        response=$(curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d "chat_id=${chat_id}" \
            -d "text=${mensaje}" \
            -d "parse_mode=Markdown" 2>&1)
        if [[ "$response" != *"\"ok\":true"* ]]; then
            echo "⚠️ Advertencia Telegram API: $response"
        else
            echo "📡 Notificación de Telegram enviada exitosamente a chat_id (${chat_id})."
        fi
    else
        echo "ℹ️ Notificación de Telegram omitida: No se configuró TELEGRAM_BOT_TOKEN ni TELEGRAM_CHAT_ID en .env ni en la base de datos (admin.configuraciones)."
    fi
}
