# =============================================================================
#  Multi Minecraft - Universal runtime image
#
#  Default (JAVA_VERSION=all): ships Java 8, 11, 17, 21, 25 and 26 side by
#  side so ONE image can run every Minecraft server ever released. Any
#  future, snapshot, EA, beta, alpha or obsolete Java version can also be
#  downloaded on-demand at runtime.
#
#  Slim variants: build with --build-arg JAVA_VERSION=8|11|17|21|25|26 to get
#  a single-JVM image for maximum lightness.
#
#  The image intentionally contains ONLY the JRE (servers never need a JDK at
#  runtime). The Spigot/BuildTools path downloads a temporary JDK at install
#  time, keeping this image as small as possible.
# =============================================================================

ARG JAVA_VERSION=all

FROM ubuntu:jammy

LABEL author="PotenFYR Studios" maintainer="support@potenfyr.in"

ARG JAVA_VERSION=all
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Base tooling + PHP (PocketMine-MP) + native libraries (Bedrock dedicated server)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        jq \
        unzip \
        xz-utils \
        tzdata \
        iproute2 \
        locales \
        php8.1-cli \
        php8.1-curl \
        php8.1-mbstring \
        php8.1-xml \
        php8.1-bcmath \
        php8.1-gmp \
        libcurl4 \
        libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8 || true

# Map Docker arch to Adoptium naming; unknown/exotic arches degrade
# gracefully (distro OpenJDK fallback below guarantees a usable JVM).
RUN case "${TARGETARCH}" in \
        amd64) echo "x64" > /tmp/ptero-arch ;; \
        arm64) echo "aarch64" > /tmp/ptero-arch ;; \
        ppc64le) echo "ppc64le" > /tmp/ptero-arch ;; \
        s390x) echo "s390x" > /tmp/ptero-arch ;; \
        riscv64) echo "riscv64" > /tmp/ptero-arch ;; \
        *) echo "unsupported" > /tmp/ptero-arch ;; \
    esac

COPY install-java.sh /usr/local/bin/install-java.sh
RUN chmod +x /usr/local/bin/install-java.sh

# Install every requested JRE; tolerate vendors/arches where a given runtime
# does not exist so the image always builds on any architecture.
RUN arch="$(cat /tmp/ptero-arch)" ; \
    if [ "${JAVA_VERSION}" = "all" ] ; then wanted="8 11 17 21 25 26" ; else wanted="${JAVA_VERSION}" ; fi ; \
    for v in ${wanted} ; do \
        if [ "${arch}" = "unsupported" ] ; then \
            echo "WARN: skipping JRE ${v} on unsupported architecture" ; \
            continue ; \
        fi ; \
        install-java.sh "${v}" "${arch}" || echo "WARN: JRE ${v} unavailable for ${arch}" ; \
    done

# Guarantee at least one working JVM even where Adoptium publishes nothing.
RUN if ! ls /opt/java/*/bin/java >/dev/null 2>&1 ; then \
        apt-get update \
        && apt-get install -y --no-install-recommends default-jre-headless \
        && rm -rf /var/lib/apt/lists/* ; \
    fi

# Keep install-java.sh available at runtime: the entrypoint uses it to
# download additional Java runtimes (e.g. JAVA_VERSION=27, GraalVM, custom URLs).
RUN rm -f /tmp/ptero-arch \
    && mkdir -p /opt/java \
    && chmod -R a+rX /opt/java

# Create container user (required by Pterodactyl, Wings, Pelican, Feather Panel)
RUN useradd -d /home/container -m -s /bin/bash container \
    && mkdir -p /home/container \
    && chown -R container:container /home/container \
    && chmod -R 777 /home/container

# Egg runtime scripts live in a dedicated root-owned directory outside the
# user-visible server directory. The panel file manager is jailed to
# /home/container, so users can never see, edit or replace them; everything
# is root:root 0755 (world-readable + executable, never writable by the
# container user). /usr/local/bin, /entrypoint.sh, /run.sh and /install.sh
# are symlinks kept for panel startup-string compatibility.
COPY install.sh entrypoint.sh run.sh install-java.sh /opt/potenfyr/
RUN chmod 755 /opt/potenfyr \
    && chown root:root /opt/potenfyr/* \
    && chmod 755 /opt/potenfyr/run.sh /opt/potenfyr/entrypoint.sh /opt/potenfyr/install.sh /opt/potenfyr/install-java.sh \
    && ln -sf /opt/potenfyr/entrypoint.sh /entrypoint.sh \
    && ln -sf /opt/potenfyr/entrypoint.sh /usr/local/bin/entrypoint.sh \
    && ln -sf /opt/potenfyr/run.sh /run.sh \
    && ln -sf /opt/potenfyr/run.sh /usr/local/bin/run.sh \
    && ln -sf /opt/potenfyr/install.sh /install.sh \
    && ln -sf /opt/potenfyr/install.sh /usr/local/bin/install.sh \
    && ln -sf /opt/potenfyr/install-java.sh /usr/local/bin/install-java.sh

# Provenance stamp surfaced at boot for supportability & audit trails.
#  Stop contract: the launcher (PID 1) traps SIGTERM/SIGINT for graceful
#  shutdown; panels and docker stop both deliver SIGTERM first, and Wings-family
#  daemons send their stop command as console text (handled by the launcher's
#  stdin stop-command watcher).
RUN echo "PotenFYR Multi Minecraft Runtime • variant=${JAVA_VERSION} • built=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > /etc/potenfyr-version

USER container
ENV USER=container HOME=/home/container PATH="/usr/local/bin:/opt/java/21/bin:${PATH}"
WORKDIR /home/container
STOPSIGNAL SIGTERM
CMD ["/bin/bash", "/entrypoint.sh"]
