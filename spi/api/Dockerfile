# 1. ETAPA DE COMPILACION (BUILD STAGE)
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

# Instalar dependencias para compilar 'docsis' desde su repositorio oficial
RUN apt-get update && apt-get install -y \
    git \
    automake \
    libtool \
    libsnmp-dev \
    bison \
    make \
    gcc \
    flex \
    libglib2.0-dev \
    libfl-dev \
    && rm -rf /var/lib/apt/lists/*

# Clonar y compilar el compilador oficial de cablemódems 'docsis'
RUN git clone https://github.com/rlaager/docsis.git /tmp/docsis \
    && cd /tmp/docsis \
    && ./autogen.sh \
    && ./configure \
    && make \
    && make install \
    && cd / \
    && rm -rf /tmp/docsis

WORKDIR /src

# Copiar archivo de proyecto e instalar dependencias NuGet
COPY ["smi-api.csproj", "./"]
RUN dotnet restore "smi-api.csproj"

# Copiar todo el código y publicar la API optimizada para producción
COPY . .
RUN dotnet publish "smi-api.csproj" -c Release -o /app/publish /p:UseAppHost=false

# 2. ETAPA DE PRODUCCION (RUNTIME STAGE)
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime

# Instalar dependencias de ejecución: cliente SNMP, wget, docker.io y librerías compartidas de glib para docsis
RUN apt-get update && apt-get install -y \
    snmp \
    libglib2.0-0 \
    wget \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/publish .

# Copiar el binario compilador compilado en la etapa build
COPY --from=build /usr/local/bin/docsis /usr/local/bin/docsis

# Exponer puerto HTTP por defecto de la API
EXPOSE 8000
ENV ASPNETCORE_URLS=http://+:8000

# Comando para ejecutar la aplicación
ENTRYPOINT ["dotnet", "SmiApi.dll"]
