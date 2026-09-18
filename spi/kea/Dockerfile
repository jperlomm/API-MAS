FROM docker.io/debian:bookworm-slim

# Evitar prompts interactivos durante la instalación
ENV DEBIAN_FRONTEND=noninteractive

# Instalar prerrequisitos para agregar repositorios externos
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    apt-transport-https \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Agregar repositorio oficial de ISC Kea (versión estable 3.0 que incluye flex-id gratis)
RUN curl -1sLf 'https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh' | bash

# Instalar Kea DHCPv4 desde el repo de ISC con soporte para PostgreSQL, hooks y Agente de Control
RUN apt-get update && apt-get install -y \
    isc-kea-dhcp4 \
    isc-kea-ctrl-agent \
    isc-kea-admin \
    isc-kea-hooks \
    isc-kea-pgsql \
    postgresql-client \
    procps \
    net-tools \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Crear directorios requeridos para sockets y ejecución de Kea con permisos estrictos (750) requeridos por Kea 3.0
RUN mkdir -p /var/run/kea /var/lib/kea /etc/kea && chmod 750 /var/run/kea

# Comando de inicio: Asegura permisos de socket, limpia pids viejos y arranca servicios
CMD ["bash", "-c", "mkdir -p /var/run/kea && chmod 750 /var/run/kea && rm -f /var/run/kea/*.pid && kea-ctrl-agent -c /etc/kea/kea-ctrl-agent.conf & exec kea-dhcp4 -c /etc/kea/kea-dhcp4.conf"]
