# 🐙 GUÍA SRE: CONFIGURACIÓN DE GIT EN EL SERVIDOR DE PRODUCCIÓN
---
Este manual contiene el procedimiento paso a paso para instalar, configurar y autenticar Git en tu servidor de producción Debian/Proxmox, permitiendo actualizar configuraciones mediante `git pull` de forma segura.

---

## ⚙️ PASO 1: Identificación inicial de Git
Al igual que en tu PC de desarrollo, lo primero es decirle a Git quién está operando en el servidor para que los registros internos de auditoría sean correctos.

Conéctate a tu servidor por SSH y ejecuta:
```bash
git config --global user.name "jperlomm"
git config --global user.email "jperlo@mmelectronica.com"
```

---

## 🔐 PASO 2: Autenticación segura con GitHub

Dado que tu repositorio `jperlomm/API-MAS` es privado o requiere autenticación para descargar cambios, debes autorizar a tu servidor para conectarse a tu cuenta de GitHub. 

La forma más profesional y segura de hacerlo es mediante **Claves SSH** (así el servidor no necesita guardar tu contraseña de GitHub).

### 1. Copiar tu Clave Pública del Servidor:
Ejecuta esto en la terminal de tu servidor para ver tu clave SSH pública (que creamos anteriormente):
```bash
cat ~/.ssh/id_rsa.pub
```
*(Verás un texto largo que empieza con `ssh-rsa` o `ssh-ed25519` y termina con `usuario@...`)*. **Selecciona todo ese texto y cópialo.**

### 2. Registrarla en GitHub:
1. Entra a tu cuenta de GitHub en la web.
2. Ve a tu **Perfil (arriba a la derecha) -> Settings -> SSH and GPG keys**.
3. Haz clic en **New SSH key**.
4. Ponle un título descriptivo (ejemplo: `Servidor-Producción-SPI`).
5. En el campo **Key**, pega el texto de tu clave pública que copiaste en el punto anterior.
6. Haz clic en **Add SSH key**.

---

## 🛠️ PASO 3: Vincular tu Carpeta de Producción a GitHub

Elige el escenario que aplique a tu estado actual en el servidor:

### 📂 ESCENARIO A: Si ya tienes la carpeta `~/spi` con archivos pero NO tiene Git
Si ya habías subido archivos mediante SCP o el script de despliegue, y deseas transformar esa carpeta en un repositorio de Git enlazado a GitHub de forma segura (sin perder archivos como tu `.env` local):

Ejecuta estos comandos en la terminal de tu servidor:
```bash
# 1. Navegar a la carpeta del proyecto
cd ~/spi

# 2. Inicializar un repositorio local vacío
git init

# 3. Vincular el repositorio local al tuyo de GitHub usando SSH
git remote add origin git@github.com:jperlomm/API-MAS.git

# 4. Traer el historial de ramas desde GitHub
git fetch origin

# 5. Configurar tu rama local para que "apunte" y rastree a la rama 'main' de GitHub
git checkout -f -B main origin/main
```
*(Nota: Al usar `-f` forzamos la alineación de archivos del servidor con los de GitHub, pero **no te preocupes por tu archivo `.env`**, ya que al estar listado en el archivo `.gitignore` no será alterado ni borrado).*

---

### 📂 ESCENARIO B: Si estás en una VM Limpia (Sin carpeta `~/spi` previa)
Si estás desplegando una VM nueva y vacía, el proceso es infinitamente más sencillo: solo debes clonar directamente tu repositorio desde GitHub:

```bash
# Clonar directamente en la ruta ~/spi del servidor
git clone git@github.com:jperlomm/API-MAS.git ~/spi
```

---

## 🚀 PASO 4: Tu flujo diario de actualizaciones en 1 segundo

Una vez configurado lo anterior, cada vez que desees aplicar un cambio que guardaste en tu PC de desarrollo:

### 1. En tu PC Local (Desarrollo):
Subes los cambios confirmados a tu cuenta de GitHub:
```bash
git push
```

### 2. En tu Servidor (SSH):
Navegas a la carpeta y descargas únicamente los cambios en 1 segundo:
```bash
cd ~/spi
git pull
```
