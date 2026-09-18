# ==========================================
# Etapa 1: Construcción (Builder Stage)
# ==========================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copiar manifiesto de dependencias e instalar
COPY package*.json ./
RUN npm install

# Copiar código fuente y compilar
COPY . .
RUN npm run build

# ==========================================
# Etapa 2: Servidor Web de Producción
# ==========================================
FROM nginx:alpine

# Limpiar directorio web por defecto de Nginx
RUN rm -rf /usr/share/nginx/html/*

# Copiar compilado final desde el constructor
COPY --from=builder /app/dist /usr/share/nginx/html

# Copiar configuración personalizada con proxy reverso
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
