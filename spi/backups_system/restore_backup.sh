#!/bin/bash
# =========================================================================
# 🛡️ SRE DISASTER RECOVERY: RESTAURACIÓN AUTOMATIZADA E INFALIBLE
# =========================================================================
# Este script realiza la limpieza completa de esquemas, inyección del dump
# SQL, resincronización de secuencias y reinicio de servicios en 1 solo paso.
#
# Uso:
#   ./restore_backup.sh /ruta/al/respaldo.sql
# O simplemente (usa el último backup generado en /opt/backups):
#   ./restore_backup.sh
# =========================================================================

set -e

BACKUP_FILE="$1"

# Si no se especifica archivo, buscar el archivo .sql más reciente en /opt/backups
if [ -z "$BACKUP_FILE" ]; then
    BACKUP_FILE=$(ls -t /opt/backups/*.sql 2>/dev/null | head -n 1 || true)
fi

if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ ERROR: No se encontró ningún archivo de respaldo válido."
    echo "Uso: $0 /ruta/al/archivo_respaldo.sql"
    exit 1
fi

echo "========================================================================="
echo "📥 INICIANDO RESTAURACIÓN INFALIBLE DE BASE DE DATOS"
echo "📄 Archivo seleccionado: $BACKUP_FILE"
echo "========================================================================="

# 1. Vaciar esquemas previo a la importación
echo "🧹 Paso 1/4: Reseteando esquemas public y admin en PostgreSQL..."
docker exec -i isp-postgres psql -U postgres -d dhcp -c \
    "DROP SCHEMA public CASCADE; DROP SCHEMA IF EXISTS admin CASCADE; CREATE SCHEMA public; CREATE SCHEMA admin;"

# 2. Inyectar el archivo de respaldo (Soporta .sql plano o comprimido .gz)
echo "📥 Paso 2/4: Importando datos de respaldo..."
if [[ "$BACKUP_FILE" == *.gz ]]; then
    gunzip -c "$BACKUP_FILE" | docker exec -i isp-postgres psql -U postgres -d dhcp
else
    docker exec -i isp-postgres psql -U postgres -d dhcp < "$BACKUP_FILE"
fi

# 3. Resincronizar secuencias de auto-incremento (Fix para user_refresh_tokens_pkey y secuencias)
echo "🔄 Paso 3/4: Resincronizando secuencias de auto-incremento de IDs..."
docker exec -i isp-postgres psql -U postgres -d dhcp -c "
DO \$\$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT table_schema, table_name, column_name, pg_get_serial_sequence(format('%I.%I', table_schema, table_name), column_name) as seq
        FROM information_schema.columns
        WHERE pg_get_serial_sequence(format('%I.%I', table_schema, table_name), column_name) IS NOT NULL
    LOOP
        EXECUTE format('SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %I.%I), 0) + 1, false);',
                       r.seq, r.column_name, r.table_schema, r.table_name);
    END LOOP;
END \$\$;"

# 4. Reiniciar servicios para cargar en memoria los datos restaurados
echo "🚀 Paso 4/4: Reiniciando contenedores Docker..."
docker compose restart

echo "========================================================================="
echo "✅ RESTAURACIÓN COMPLETADA CON ÉXITO ABSOLUTO"
echo "========================================================================="
