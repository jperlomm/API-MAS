# 🗄️ GUÍA RÁPIDA: MIGRACIÓN DE BASE DE DATOS EN 4 PASOS (SPI MAS)
---
Este manual resume el procedimiento exacto y ultra-práctico utilizado para migrar la base de datos histórica hacia el nuevo servidor de producción bajo Docker Compose.

---

### 📋 CONFIGURACIÓN PREVIA:
Durante la migración, tu archivo `docker-compose.yml` tiene declarado temporalmente el servicio `pg_legacy_temp` en el puerto **`5435`**. Una vez finalizada la migración, este servicio se comentará o eliminará del compose para dejar únicamente el motor de producción (`isp-postgres` en puerto `5432`) activo.

---

## 🚀 PROCESO DE MIGRACIÓN EN 4 PASOS

### 📦 PASO 1: Copiar el dump comprimido al servidor (SCP)
Desde la terminal de tu computadora local de desarrollo, copia tu volcado comprimido de pruebas hacia el directorio home del usuario en el servidor Proxmox:
```bash
scp "/home/usuario/Documentos/antigravity/SPI-V1/POSTREGRES LEGACY/spi40db.dump.gz" usuario@192.168.2.107:/home/usuario/
```

---

### 💾 PASO 2: Descomprimir y restaurar el dump en el contenedor Legacy
Conéctate por SSH a tu servidor y ejecuta la descompresión física del archivo, seguida de la inyección directa al contenedor temporal de base de datos `pg_legacy_temp` (puerto `5435`):

#### 1. Descomprimir el archivo en el servidor:
```bash
gunzip -f /home/usuario/spi40db.dump.gz
```
*(Esto extraerá el archivo de texto SQL plano `/home/usuario/spi40db.dump` listo para usar).*

#### 2. Restaurar la base de datos dentro del contenedor temporal:
```bash
docker exec -i pg_legacy_temp psql -U postgres -d pg_legacy_temp < /home/usuario/spi40db.dump
```

---

### ⚙️ PASO 3: Levantar funciones ETL y datos estructurales de bajo cambio
Carga el script `postgres_migration_complete.sql` en tu contenedor de producción. Este paso realiza de forma automática:
1. La conexión FDW hacia el contenedor legacy (`pg_legacy_temp` en el puerto `5435`).
2. La migración de datos fijos estructurales (Planes/servicios, subredes DHCP, cabeceras CMTS y marcas de modems) para satisfacer restricciones de Foreign Keys.
3. El registro de la función de migración dinámica.

```bash
docker exec -i isp-postgres psql -U postgres -d dhcp < /home/usuario/postgres_migration_complete.sql
```

---

### 📈 PASO 4: Ejecutar la migración dinámica por CMTS
Corre la migración por consola especificando el ID del CMTS que deseas migrar (ejemplo, el `3` para Clucellas). Esto migrará de golpe todos los clientes, cable modems y suscripciones de ese nodo en menos de 1 segundo:
```bash
docker exec -it isp-postgres psql -U postgres -d dhcp -c "SELECT * FROM admin.migrar_datos_por_cmts(3);"
```

---

## 🧹 PASO FINAL: Limpieza de Producción
Una vez que hayas migrado todos los CMTS y verificado la consistencia:
1. Abre tu `docker-compose.yml` en el servidor y comenta o elimina el servicio de la base de datos temporal `pg_legacy_temp`.
2. Reinicia tus contenedores para eliminar rastros de la base de datos temporal:
   ```bash
   docker compose up -d --remove-orphans
   ```
3. (Opcional) Elimina el FDW en la base de datos de producción ejecutando:
   ```bash
   docker exec -it isp-postgres psql -U postgres -d dhcp -c "DROP SCHEMA IF EXISTS legacy CASCADE; DROP SERVER IF EXISTS legacy_server CASCADE;"
   ```
4. Borra el archivo de dump temporal en el servidor para liberar espacio de almacenamiento:
   ```bash
   rm -f /home/usuario/spi40db.dump
   ```
