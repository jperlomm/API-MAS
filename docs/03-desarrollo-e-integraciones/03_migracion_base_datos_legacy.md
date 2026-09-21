# 🗄️ GUÍA RÁPIDA: MIGRACIÓN DE BASE DE DATOS EN 5 PASOS (SPI MAS)
---
Este manual resume el procedimiento real, optimizado e ininterrumpido utilizado para migrar la base de datos histórica hacia tu nuevo servidor de producción sin saturar recursos de red o disco.

---

## 🚀 PROCESO DE MIGRACIÓN PASO A PASO

### 📦 PASO 1: Copiar el dump comprimido al Servidor (Desde tu PC Local)
Abre una terminal en tu **PC local de desarrollo** y ejecuta este comando para subir el archivo comprimido a la carpeta temporal `/tmp/` del servidor (tardará apenas un par de segundos):
```bash
scp "/home/usuario/Documentos/antigravity/SPI-V1/POSTREGRES LEGACY/spi40db.dump.gz" usuario@192.168.2.106:/tmp/
```

---

### 🖥️ PASO 2: Conectarse al Servidor por SSH
Una vez subido el archivo, conéctate a la consola de tu servidor Proxmox/Debian desde tu PC local:
```bash
ssh usuario@192.168.2.106
```

---

### 🖥️ PASO 3: Iniciar el Contenedor PostgreSQL Temporal (En el Servidor)
Ya dentro de la terminal del servidor, ejecuta este comando para iniciar un Postgres 15 limpio e independiente en el puerto **`5435`** con la base de datos **`spi_legacy`**:
```bash
docker run --name pg_legacy_temp \
  -e POSTGRES_DB=spi_legacy \
  -e POSTGRES_PASSWORD=P0stgr3s_legacy_pwd \
  -p 5435:5432 \
  -d postgres:15
```

---

### 🖥️ PASO 4: Descomprimir y restaurar al vuelo (En el Servidor)
Espera unos segundos para que se inicialice el motor de base de datos dentro del contenedor temporal, y luego ejecuta la descompresión y restauración en una sola línea de tubería para no desperdiciar espacio de disco:
```bash
# 1. Esperar que inicialice el motor de base de datos
sleep 6

# 2. Descomprimir y restaurar de forma 100% local al vuelo
gunzip -c /tmp/spi40db.dump.gz | docker exec -i pg_legacy_temp psql -U postgres -d spi_legacy
```

---

### 🖥️ PASO 5: Cargar ETL, Migrar CMTS y realizar la Limpieza
Una vez restaurados todos tus datos sandbox en el puerto `5435`, realizamos el despliegue del script de migración, la corrida de datos dinámica y eliminamos los recursos temporales:

#### 1. Inyectar el archivo de funciones ETL dentro de tu contenedor de producción activo:
```bash
docker exec -i isp-postgres psql -U postgres -d dhcp < /home/usuario/postgres_migration_complete.sql
```
*(Este script conecta automáticamente el FDW al puerto `5435`, migra datos estructurales de bajo cambio y registra las funciones ETL).*

#### 2. Ejecutar la migración dinámica para tu CMTS 3 (Clucellas) de forma local:
```bash
docker exec -it isp-postgres psql -U postgres -d dhcp -c "SELECT * FROM admin.migrar_datos_por_cmts(3);"
```

#### 3. Eliminar el archivo temporal del disco del servidor:
```bash
rm -f /tmp/spi40db.dump.gz
```

#### 4. Apagar, destruir el contenedor temporal y limpiar el FDW:
```bash
# Apagar y remover el contenedor sandbox
docker stop pg_legacy_temp && docker rm pg_legacy_temp

# (Opcional) Borrar rastro de conexión FDW dentro de producción
docker exec -it isp-postgres psql -U postgres -d dhcp -c "DROP SCHEMA IF EXISTS legacy CASCADE; DROP SERVER IF EXISTS legacy_server CASCADE;"
```
