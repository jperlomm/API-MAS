# 🗄️ GUÍA RÁPIDA: MIGRACIÓN DE BASE DE DATOS EN 4 PASOS (SPI MAS)
---
Este manual resume el procedimiento exacto y ultra-práctico utilizado para migrar la base de datos histórica hacia el nuevo servidor de producción bajo Docker Compose.

---

### 📋 CONFIGURACIÓN PREVIA:
Durante la migración, tu archivo `docker-compose.yml` tiene declarado temporalmente el servicio `pg_legacy_temp` en el puerto **`5435`**. Una vez finalizada la migración, este servicio se comentará o eliminará del compose para dejar únicamente el motor de producción (`isp-postgres` en puerto `5432`) activo.

---

## 🚀 PROCESO DE MIGRACIÓN EN 4 PASOS

### 📦 PASO 1: Copiar el dump legacy al servidor (SCP)
Desde la terminal de tu computadora local de desarrollo, copia el archivo de respaldo histórico (`spiOLD.sql` o `pg_legacy_temp.sql`) hacia la carpeta de tu usuario en el servidor Proxmox:
```bash
scp ~/Documentos/spiOLD.sql usuario@192.168.2.107:/home/usuario/
```

---

### 💾 PASO 2: Restaurar el dump en el contenedor Legacy (Docker Exec)
Una vez copiado el archivo, conéctate por SSH al servidor y restáuralo dentro del contenedor temporal de base de datos legacy `pg_legacy_temp` (puerto `5435`):
```bash
docker exec -i pg_legacy_temp psql -U postgres -d pg_legacy_temp < /home/usuario/spiOLD.sql
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
