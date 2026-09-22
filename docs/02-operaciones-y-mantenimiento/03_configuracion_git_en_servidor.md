# 🐙 GUÍA SRE: GESTIÓN DE CLAVES SSH Y CONFIGURACIÓN DE GIT EN EL SERVIDOR
---
Este manual explica cómo generar y administrar claves SSH para autenticación con **GitHub** y acceso remoto **sin contraseña**, así como el procedimiento para vincular e interactuar con Git en tu servidor de producción Debian/Proxmox.

---

## 🔑 1. GENERACIÓN Y GESTIÓN DE CLAVES SSH

Las claves SSH funcionan en par:
- **Clave Privada (`id_ed25519` o `id_rsa`):** NUNCA se comparte ni se envía por red. Permanece segura en la máquina origen (`~/.ssh/`).
- **Clave Pública (`id_ed25519.pub` or `id_rsa.pub`):** Se copia al servidor destino o a servicios como GitHub (`~/.ssh/authorized_keys` o GitHub SSH Keys).

### 🛠️ Paso 1.1: Generar un nuevo par de claves SSH
Si estás en una máquina nueva (PC local o Servidor) que aún no tiene claves generadas en `~/.ssh/`:

```bash
# Opción recomendada (Algoritmo moderno Ed25519)
ssh-keygen -t ed25519 -C "jperlo@mmelectronica.com"

# Opción alternativa tradicional (RSA 4096 bits)
ssh-keygen -t rsa -b 4096 -C "jperlo@mmelectronica.com"
```
*Cuando pida la ruta, presiona `Enter` para aceptar la ubicación por defecto (`~/.ssh/`).*
*Cuando pida passphrase (contraseña), puedes presionar `Enter` para no requerir contraseña cada vez que la uses.*

### 📄 Paso 1.2: Visualizar tu Clave Pública
Para copiar tu clave pública a GitHub o a otro servidor:

```bash
# Si creaste llave Ed25519:
cat ~/.ssh/id_ed25519.pub

# Si creaste llave RSA:
cat ~/.ssh/id_rsa.pub
```
*(Copia todo el texto resultante que comienza con `ssh-ed25519 ...` o `ssh-rsa ...`)*.

---

## 🔐 2. USO DE CLAVES SSH EN GITHUB (`git@github.com`)

Para que el servidor o tu PC de desarrollo se comuniquen con tu repositorio privado `jperlomm/API-MAS` en GitHub sin ingresar usuario y contraseña:

### Paso 2.1: Agregar la Clave Pública a tu cuenta de GitHub
1. Entra a tu cuenta en GitHub.
2. Ve a **Settings -> SSH and GPG keys**.
3. Haz clic en **New SSH key**.
4. En **Title**, escribe un nombre descriptivo (ej. `Servidor-Produccion-SPI` o `PC-Desarrollo-Local`).
5. En **Key**, pega la clave pública que copiaste en el paso 1.2.
6. Haz clic en **Add SSH key**.

### Paso 2.2: Probar la conexión con GitHub
Ejecuta el siguiente comando para verificar la autenticación:
```bash
ssh -T git@github.com
```
*(Respuesta esperada: `Hi jperlomm! You've successfully authenticated, but GitHub does not provide shell access.`)*.

---

## 🖥️ 3. USO DE CLAVES SSH PARA ACCESO AL SERVIDOR SIN CONTRASEÑA

Para conectarte desde tu PC de desarrollo hacia el servidor Proxmox o ejecutar scripts automatizados (`deploy.sh`, `scp`, `rsync`) sin que te solicite contraseña en cada ejecución:

### Paso 3.1: Copiar la Clave Pública de tu PC Local al Servidor
Desde la terminal de tu **PC local de desarrollo**, ejecuta:

```bash
ssh-copy-id usuario@192.168.2.106
```
*(Te pedirá la contraseña del usuario `11Smme27` por última vez. A partir de este momento, la clave pública de tu PC quedará guardada en el archivo `~/.ssh/authorized_keys` del servidor).*

### Paso 3.2: Método manual (Alternativa si `ssh-copy-id` no está disponible)
Si prefieres hacerlo a mano:
1. Copia el contenido de `~/.ssh/id_rsa.pub` de tu PC local.
2. En el servidor, abre o crea el archivo de llaves autorizadas:
   ```bash
   nano ~/.ssh/authorized_keys
   ```
3. Pega la clave pública en una nueva línea, guarda (`Ctrl+O`) y sal (`Ctrl+X`).
4. Asegura los permisos correctos en el servidor:
   ```bash
   chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
   ```

---

## ⚙️ 4. CONFIGURACIÓN DE GIT EN EL SERVIDOR

### Paso 4.1: Identificación de usuario en el Servidor
En la terminal del servidor, establece tu identidad de auditoría:
```bash
git config --global user.name "jperlomm"
git config --global user.email "jperlo@mmelectronica.com"
```

---

## 🛠️ 5. VINCULAR LA CARPETA DE PRODUCCIÓN A GITHUB

### 📂 ESCENARIO A: Si la carpeta `~/spi` ya existe pero NO tiene Git
Para convertir la carpeta existente en un repositorio vinculado a GitHub sin sobreescribir archivos locales como `.env`:

```bash
cd ~/spi
git init
git remote add origin git@github.com:jperlomm/API-MAS.git
git fetch origin
git checkout -f -B main origin/main
```

### 📂 ESCENARIO B: En una VM completamente nueva (Sin carpeta `~/spi`)
```bash
git clone git@github.com:jperlomm/API-MAS.git ~/spi
```

---

## 🚀 6. FLUJO DIARIO DE TRABAJO (PUSH & PULL)

1. **En PC Local (Desarrollo):**
   ```bash
   git add .
   git commit -m "Descripción de los cambios"
   git push
   ```

2. **En Servidor (Producción via SSH):**
   ```bash
   cd ~/spi
   git pull
   ```
