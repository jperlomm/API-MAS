FROM docker.io/postgres:15

# Variables de entorno para el idioma y la zona horaria
ENV LANG=es_ES.UTF-8
ENV TZ="America/Buenos_Aires"

# Configurar el sistema en Español y la hora local
RUN apt-get update && apt-get install -y locales \
    && localedef -i es_ES -c -f UTF-8 -A /usr/share/locale/locale.alias es_ES.UTF-8 \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Instalar herramientas básicas de red y administración útiles para el ISP
RUN apt-get update && apt-get install -y \
    mc wget procps iputils-ping net-tools iptables sudo \
    && rm -rf /var/lib/apt/lists/*

# Personalización del Prompt (Estética de consola para producción)
RUN echo 'PS1="\[\e[4;41;2m\e[1;38m\] \$ISP_NAME \[\e[30m\]▐\[\e[103m\e[1;30m\] POSTGRES ▐\[\e[1;47m\] \w \[\e[m\] # "' >> /root/.bashrc \
    && echo "alias ll='ls -l --color=auto'" >> /root/.bashrc \
    && echo "alias ls='ls --color=auto'" >> /root/.bashrc
