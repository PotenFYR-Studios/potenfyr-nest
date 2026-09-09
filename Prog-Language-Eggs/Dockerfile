# =============================================================================
#  Multi-Language Eggs - Single Image, All Runtimes Architecture
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Prog-Language-Eggs)
#
#  ONE image for every language and panel:
#    - Language runtimes pre-baked where upstream ships them for the platform
#    - Anything missing self-provisions on demand inside the container via
#      install-runtime.sh (versions resolved from live upstream feeds)
#    - linux/amd64, linux/arm64 and linux/arm/v7 published; other host CPUs
#      work through per-engine availability checks at install time
# =============================================================================

# Debian bookworm: its armhf packages configure cleanly under QEMU emulation,
# unlike Ubuntu jammy whose libc-bin/ldconfig trigger crashes on linux/arm/v7
# ("Errors were encountered while processing: libc-bin"). Slimmer base too.
FROM debian:bookworm-slim

LABEL author="PotenFYR Studios" maintainer="support@potenfyr.in"
LABEL org.opencontainers.image.source="https://github.com/potenfyr-studios/prog-language-eggs"
LABEL org.opencontainers.image.description="Single multi-language runtime image across Pterodactyl, Pelican, Feather Panel, PufferPanel and plain Docker"

# Kept for local/custom builds; CI always passes "all".
ARG RUNTIME_VARIANT=all
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    USER=container \
    HOME=/home/container \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    GOPATH=/home/container/go \
    CARGO_HOME=/home/container/.cargo \
    RUSTUP_HOME=/opt/rustup \
    IMAGE_VARIANT=${RUNTIME_VARIANT}

# Stop contract: the launcher (PID 1) traps SIGTERM for graceful shutdown;
# panels and docker stop both deliver SIGTERM first.
STOPSIGNAL SIGTERM

# 1. Base tools, networking, archive utilities & shared dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        jq \
        unzip \
        tar \
        xz-utils \
        bzip2 \
        zip \
        git \
        gnupg \
        iproute2 \
        tzdata \
        locales \
        procps \
        dnsutils \
        libssl-dev \
        zlib1g-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 2. Compilers & Build Tools (native compilation, node-gyp, source builds)
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        g++ \
        clang \
        make \
        cmake \
        ninja-build \
        gfortran \
        fp-compiler \
        nasm \
    && rm -rf /var/lib/apt/lists/*

# 3. Node.js LTS & global tooling
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g --no-fund --no-audit npm pnpm yarn typescript ts-node tsx nodemon pm2 \
    && mkdir -p /opt/runtimes/node/bin \
    && ln -sf /usr/bin/node /opt/runtimes/node/bin/node 2>/dev/null || true \
    && rm -rf /var/lib/apt/lists/*

# 4. Bun (amd64/arm64 upstream; other arches self-provision on demand)
RUN ARCH="$(uname -m)" \
    && case "$ARCH" in \
        x86_64|amd64) BUN_ARCH="x64" ;; \
        aarch64|arm64) BUN_ARCH="aarch64" ;; \
        *) BUN_ARCH="" ;; \
    esac \
    && if [ -n "${BUN_ARCH}" ]; then \
        curl -fsSL "https://github.com/oven-sh/bun/releases/latest/download/bun-linux-${BUN_ARCH}.zip" -o /tmp/bun.zip \
        && unzip -qo /tmp/bun.zip -d /tmp/bun-extract \
        && mkdir -p /opt/runtimes/bun/bin \
        && mv /tmp/bun-extract/bun-linux-*/bun /opt/runtimes/bun/bin/bun \
        && chmod -R 755 /opt/runtimes/bun \
        && ln -sf /opt/runtimes/bun/bin/bun /opt/runtimes/bun/bin/bunx \
        && ln -sf /opt/runtimes/bun/bin/bun /usr/local/bin/bun \
        && ln -sf /opt/runtimes/bun/bin/bunx /usr/local/bin/bunx \
        && rm -rf /tmp/bun.zip /tmp/bun-extract; \
    else \
        echo "[build] Bun not packaged for $ARCH - will self-provision on demand."; \
    fi

# 5. Deno (amd64/arm64 upstream; other arches self-provision on demand)
RUN ARCH="$(uname -m)" \
    && case "$ARCH" in \
        x86_64|amd64) DENO_ARCH="x86_64" ;; \
        aarch64|arm64) DENO_ARCH="aarch64" ;; \
        *) DENO_ARCH="" ;; \
    esac \
    && if [ -n "${DENO_ARCH}" ]; then \
        curl -fsSL "https://github.com/denoland/deno/releases/latest/download/deno-${DENO_ARCH}-unknown-linux-gnu.zip" -o /tmp/deno.zip \
        && mkdir -p /opt/runtimes/deno/bin \
        && unzip -qo /tmp/deno.zip -d /opt/runtimes/deno/bin \
        && chmod -R 755 /opt/runtimes/deno \
        && ln -sf /opt/runtimes/deno/bin/deno /usr/local/bin/deno \
        && rm -f /tmp/deno.zip; \
    else \
        echo "[build] Deno not packaged for $ARCH - will self-provision on demand."; \
    fi

# 6. Python 3 & Astral uv (uv is amd64/arm64; system python3 serves everywhere)
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
    && rm -rf /var/lib/apt/lists/* \
    && ARCH="$(uname -m)" \
    && case "$ARCH" in \
        x86_64|amd64) UV_ARCH="x86_64" ;; \
        aarch64|arm64) UV_ARCH="aarch64" ;; \
        *) UV_ARCH="" ;; \
    esac \
    && if [ -n "${UV_ARCH}" ]; then \
        curl -fsSL "https://github.com/astral-sh/uv/releases/latest/download/uv-${UV_ARCH}-unknown-linux-gnu.tar.gz" -o /tmp/uv.tar.gz \
        && tar -xzf /tmp/uv.tar.gz -C /tmp \
        && mkdir -p /opt/runtimes/uv/bin \
        && mv /tmp/uv-*/uv /tmp/uv-*/uvx /opt/runtimes/uv/bin/ \
        && chmod -R 755 /opt/runtimes/uv \
        && ln -sf /opt/runtimes/uv/bin/uv /usr/local/bin/uv \
        && ln -sf /opt/runtimes/uv/bin/uvx /usr/local/bin/uvx \
        && rm -rf /tmp/uv.tar.gz /tmp/uv-*; \
    else \
        echo "[build] uv not packaged for $ARCH - system pip/venv stays active."; \
    fi

# 7. Go toolchain
RUN apt-get update && apt-get install -y --no-install-recommends golang-go \
    && mkdir -p /opt/runtimes/go/bin \
    && ln -sf /usr/bin/go /opt/runtimes/go/bin/go 2>/dev/null || true \
    && rm -rf /var/lib/apt/lists/*
# 8. Rust & Cargo via rustup
RUN export RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo \
    && (curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal || true) \
    && chmod -R 777 /opt/cargo /opt/rustup 2>/dev/null || true

# 9. PHP & Composer
RUN apt-get update && apt-get install -y --no-install-recommends \
        php-cli \
        php-curl \
        php-mbstring \
        php-xml \
        php-zip \
        php-bcmath \
    && rm -rf /var/lib/apt/lists/* \
    && (curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer || true)

# 10. Ruby & Bundler
RUN apt-get update && apt-get install -y --no-install-recommends ruby ruby-dev \
    && gem install bundler --no-document 2>/dev/null || true \
    && rm -rf /var/lib/apt/lists/*

# 11. Java OpenJDK + Maven
RUN apt-get update && apt-get install -y --no-install-recommends \
        default-jdk-headless \
        default-jre-headless \
        maven \
    && rm -rf /var/lib/apt/lists/*

# 12. .NET SDK via the official installer (auto-detects amd64/arm64/arm;
#     apt feeds do not carry armhf, so distro packages are unusable there).
#     The SDK bundle includes the ASP.NET Core shared runtime.
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet \
    && rm -f /tmp/dotnet-install.sh \
    && ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && dotnet --list-sdks

# 13. Interpreted languages (Lua, Perl, Tcl, Prolog)
RUN apt-get update && apt-get install -y --no-install-recommends \
        lua5.4 \
        luajit \
        perl \
        tcl \
        swi-prolog \
    && rm -rf /var/lib/apt/lists/*

# 14. Multi-panel working directories and non-root container user
#     /opt/potenfyr: egg-owned state dir (self-updated launcher + hashes).
#     It is writable by the container user but lives OUTSIDE the user's data
#     volume, so launcher internals are never exposed in /home/container.
RUN groupadd -g 988 container 2>/dev/null || true \
    && useradd -d /home/container -m -u 988 -g 988 container 2>/dev/null || true \
    && mkdir -p /opt/runtimes /opt/potenfyr /home/container /server /app /mnt/server \
    && chmod -R 777 /opt/runtimes /home/container /server /app /mnt/server /tmp \
    && chown -R 988:988 /opt/potenfyr

# 15. Runtime orchestration & installation scripts
COPY entrypoint.sh /entrypoint.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY run.sh /run.sh
COPY run.sh /usr/local/bin/run.sh
COPY install.sh /install.sh
COPY install.sh /usr/local/bin/install.sh
COPY install-runtime.sh /usr/local/bin/install-runtime.sh
COPY resolve-version.sh /usr/local/bin/resolve-version.sh

RUN sed -i 's/\r$//' /entrypoint.sh /run.sh /install.sh /usr/local/bin/*.sh \
    && chmod +x /entrypoint.sh \
                /run.sh \
                /install.sh \
                /usr/local/bin/entrypoint.sh \
                /usr/local/bin/run.sh \
                /usr/local/bin/install.sh \
                /usr/local/bin/install-runtime.sh \
                /usr/local/bin/resolve-version.sh

# 16. Provenance stamp surfaced at boot for supportability & audit trails
RUN echo "PotenFYR Multi-Language Runtime • variant=all • built=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > /etc/potenfyr-version

# 17. PATH configuration
ENV PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:/opt/cargo/bin:/opt/go/bin:/opt/runtimes/bin:/opt/runtimes/node/bin:/opt/runtimes/bun/bin:/opt/runtimes/deno/bin:/opt/runtimes/uv/bin:/home/container/.local/bin:/home/container/bin:/home/container/node_modules/.bin:${PATH}"

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

CMD ["/bin/bash", "/entrypoint.sh"]
