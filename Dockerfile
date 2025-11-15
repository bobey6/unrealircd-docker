# syntax=docker/dockerfile:1.7
FROM debian:bookworm-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV UNREALIRCD_USER=unreal \
    UNREALIRCD_HOME=/opt/unrealircd \
    UNREALIRCD_ROOT=/opt/unrealircd/unrealircd

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        gdb \
        libssl-dev \
        libpcre2-dev \
        libargon2-dev \
        libsodium-dev \
        libc-ares-dev \
        libcurl4-openssl-dev \
        wget \
        ca-certificates \
        tar \
        xz-utils \
        perl \
        autoconf \
        automake \
        libtool \
        gettext-base \
        certbot \
        python3-certbot-dns-cloudflare \
        python3-certbot-dns-digitalocean \
        gosu \
        openssl \
        python3 \
        python3-venv \
        curl && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -d ${UNREALIRCD_HOME} -s /bin/bash ${UNREALIRCD_USER}

USER ${UNREALIRCD_USER}
WORKDIR /tmp/unrealircd-src

RUN set -eux; \
    wget --trust-server-names https://www.unrealircd.org/downloads/unrealircd-latest.tar.gz; \
    TARFILE=$(find . -maxdepth 1 -name 'unrealircd-*.tar.gz' -print -quit); \
    [[ -n "${TARFILE}" ]] || { echo "Unable to locate downloaded UnrealIRCd tarball" >&2; exit 1; }; \
    tar -xzf "${TARFILE}"; \
    SRC_DIR=$(find . -maxdepth 1 -type d -name 'unrealircd-*' -print -quit); \
    [[ -n "${SRC_DIR}" ]] || { echo "Unable to locate extracted UnrealIRCd sources" >&2; exit 1; }; \
    cd "${SRC_DIR}"; \
    printf '%s\n' \
        'BASEPATH="${UNREALIRCD_ROOT}"' \
        'BINDIR="${UNREALIRCD_ROOT}/bin"' \
        'DATADIR="${UNREALIRCD_ROOT}"' \
        'CONFDIR="${UNREALIRCD_ROOT}/conf"' \
        'MODULESDIR="${UNREALIRCD_ROOT}/modules"' \
        'LOGDIR="${UNREALIRCD_ROOT}/logs"' \
        'CACHEDIR="${UNREALIRCD_ROOT}/cache"' \
        'DOCDIR="${UNREALIRCD_ROOT}/doc"' \
        'TMPDIR="${UNREALIRCD_ROOT}/tmp"' \
        'PRIVATELIBDIR="${UNREALIRCD_ROOT}/lib"' \
        'SSLDIR=""' \
        'CURLDIR=""' \
        'REMOTEINC=""' \
        'NOOPEROVERRIDE=""' \
        'OPEROVERRIDEVERIFY=""' \
        'NICKNAMEHISTORYLENGTH="2000"' \
        'MAXCONNECTIONS_REQUEST="auto"' \
        'GENCERTIFICATE="0"' \
        'EXTRAPARA=""' \
        'SANITIZER=""' \
        'GEOIP="classic"' \
        'INSTALLCURL="0"' \
        > config.settings; \
    ./Config -quick; \
    make -j"$(nproc)"; \
    make install; \
    cd /tmp; \
    rm -rf /tmp/unrealircd-src

USER root
WORKDIR /

RUN ln -sf ${UNREALIRCD_ROOT}/unrealircd /usr/local/bin/unrealircd && \
    mkdir -p /opt/bootstrap/conf && \
    mkdir -p ${UNREALIRCD_ROOT}/tls-certs && \
    chown -R ${UNREALIRCD_USER}:${UNREALIRCD_USER} ${UNREALIRCD_HOME}

COPY conf /opt/bootstrap/conf
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 6697 80

VOLUME ["/opt/unrealircd/unrealircd/logs", "/etc/letsencrypt"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
