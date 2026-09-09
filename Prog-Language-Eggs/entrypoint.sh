#!/bin/bash
# =============================================================================
#  Multi-Language Eggs - Container Entrypoint
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Prog-Language-Eggs)
#
#  Multi-Panel Support:
#    - Pterodactyl Panel (Wings Daemon)
#    - Pelican Panel (Pelican Wings)
#    - Feather Panel (feather-panel / renoki-co)
#    - PufferPanel
#    - Jexactyl / Wisp (Pterodactyl forks)
#    - Standalone Docker & Kubernetes (Helm / Pods / Compose)
# =============================================================================

# --- Visual theme -------------------------------------------------------------
# Default: Prog-Language Eggs agent theme (Hermes-agent style console output).
# Restore the previous PotenFYR theme with CLI_THEME=classic.
CLI_THEME="${CLI_THEME:-prog}"
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_CYAN=$'\033[36m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_MAGENTA=$'\033[35m'
C_BLUE=$'\033[34m'
C_WHITE=$'\033[37m'
C_DIM=$'\033[2m'
C_GOLD=$'\033[33m'
C_LIME=$'\033[92m'

if [ "${CLI_THEME}" = "classic" ]; then
    log()   { printf "%b %b\n" "${C_CYAN}${C_BOLD}[PotenFYR]${C_RESET}" "$*"; }
    ok()    { printf "%b %b\n" "${C_GREEN}${C_BOLD}[PotenFYR][✓]${C_RESET}" "$*"; }
    warn()  { printf "%b %b\n" "${C_YELLOW}${C_BOLD}[PotenFYR][!]${C_RESET}" "${C_YELLOW}$*${C_RESET}"; }
    error() { printf "%b %b\n" "${C_RED}${C_BOLD}[PotenFYR][✗]${C_RESET}" "${C_RED}$*${C_RESET}"; _egg_error_log "entrypoint" "$*"; }
    info()  { printf "%b %b\n" "${C_BLUE}${C_BOLD}[PotenFYR][i]${C_RESET}" "$*"; }
else
    log()   { printf "%b %b\n" "${C_LIME}${C_BOLD}</> prog-language-eggs${C_RESET}${C_DIM} ▸${C_RESET}" "$*"; }
    ok()    { printf "%b %b\n" "${C_LIME}${C_BOLD}</> prog-language-eggs ✔${C_RESET}" "${C_GREEN}$*${C_RESET}"; }
    warn()  { printf "%b %b\n" "${C_GOLD}${C_BOLD}</> prog-language-eggs ⚠${C_RESET}" "${C_YELLOW}$*${C_RESET}"; }
    error() { printf "%b %b\n" "${C_RED}${C_BOLD}</> prog-language-eggs ✖${C_RESET}" "${C_RED}$*${C_RESET}"; _egg_error_log "entrypoint" "$*"; }
    info()  { printf "%b %b\n" "${C_CYAN}${C_BOLD}</> prog-language-eggs ℹ${C_RESET}" "$*"; }
fi

# --- Troubleshooting infrastructure ---------------------------------------------
# phase(): clean dim section headers so boot logs are scannable top-to-bottom.
# _egg_error_log(): central append-only error journal (egg-level failures only)
# at .logs/launcher-errors.log so failures can be diagnosed after the fact even
# when panel scrollback is gone. Both the entrypoint and the launcher append
# here; every styled error line is journalled automatically as well.
phase() { printf "\n%b── %s %b\n" "${C_DIM}" "$*" "────────────────────────${C_RESET}"; }

ERROR_LOG=""
_egg_error_log() {
    if [ -z "${ERROR_LOG}" ]; then
        local d="${ACTIVE_WORK_DIR:-${PWD}}/.logs"
        if mkdir -p "${d}" 2>/dev/null && [ -w "${d}" ]; then
            ERROR_LOG="${d}/launcher-errors.log"
        else
            ERROR_LOG="/tmp/potenfyr-errors.log"
        fi
    fi
    printf '[%s] [%s] [panel=%s] %s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date)" \
        "${1:-egg}" "${PANEL_TYPE:-unknown}" "${2:-unknown error}" \
        >> "${ERROR_LOG}" 2>/dev/null || true
}

# --- Security baseline ----------------------------------------------------------
# Files created by the launcher are group/other-readable but not writable; core
# dumps are disabled so crashes cannot eat server disk space.
umask 022
ulimit -c 0 2>/dev/null || true

export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_CACHE_DIR=false
export NPM_CONFIG_UPDATE_NOTIFIER=false
export NPM_CONFIG_FUND=false

# -----------------------------------------------------------------------------
# 1. Multi-Panel Working Directory Resolution
# -----------------------------------------------------------------------------
if [ -d "/home/container" ]; then
    cd /home/container 2>/dev/null || true
    ACTIVE_WORK_DIR="/home/container"
elif [ -d "/app" ]; then
    cd /app 2>/dev/null || true
    ACTIVE_WORK_DIR="/app"
elif [ -d "/server" ]; then
    cd /server 2>/dev/null || true
    ACTIVE_WORK_DIR="/server"
elif [ -d "/workspace" ]; then
    cd /workspace 2>/dev/null || true
    ACTIVE_WORK_DIR="/workspace"
else
    ACTIVE_WORK_DIR="${PWD}"
fi

export WORK_DIR="${ACTIVE_WORK_DIR}"

# -----------------------------------------------------------------------------
# 2. Multi-Panel Port & Network Resolution
# -----------------------------------------------------------------------------
# Snapshot which port variables the PANEL actually injected BEFORE we
# normalize them - used by detection below (Heroku-style check requires an
# unset SERVER_PORT; our exports below would otherwise always poison it).
ORIGINAL_SERVER_PORT="${SERVER_PORT:-}"

ACTIVE_PORT="${SERVER_PORT:-${PORT:-${FEATHER_PORT:-${PUFFER_PORT:-${ALLOCATED_PORT:-${HTTP_PORT:-8080}}}}}}"
export PORT="${ACTIVE_PORT}"
export SERVER_PORT="${ACTIVE_PORT}"
export APP_PORT="${ACTIVE_PORT}"
export HTTP_PORT="${ACTIVE_PORT}"
export HOST="0.0.0.0"
export BIND_ADDRESS="0.0.0.0"

# -----------------------------------------------------------------------------
# 3. Multi-Panel Host Detection (accurate, multi-panel, multi-platform)
# -----------------------------------------------------------------------------
# Detection strategy (most specific -> most generic), exporting both a human
# label and a machine family so launchers can adapt behaviour per platform:
#
#   FAMILY wings    : Pterodactyl, Pelican, Jexactyl, Wisp, Emerald (Wings-based)
#   FAMILY feather  : Feather Panel
#   FAMILY puffer   : PufferPanel
#   FAMILY k8s      : Kubernetes / OpenShift / Nomad orchestrators
#   FAMILY paas     : Railway / Render / Fly.io / Heroku-style platforms
#   FAMILY docker   : Plain Docker / Podman / containerd
#
PANEL_TYPE="Docker / Standalone"
PANEL_FAMILY="docker"

if [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
    PANEL_TYPE="Kubernetes Pod"
    PANEL_FAMILY="k8s"
elif [ -n "${FLY_APP_NAME:-}" ] || [ -n "${FLY_MACHINE_ID:-}" ]; then
    PANEL_TYPE="Fly.io"
    PANEL_FAMILY="paas"
elif [ -n "${RAILWAY_ENVIRONMENT:-}" ] || [ -n "${RAILWAY_PROJECT_ID:-}" ]; then
    PANEL_TYPE="Railway"
    PANEL_FAMILY="paas"
elif [ -n "${RENDER_SERVICE_NAME:-}" ] || [ -n "${RENDER_INTERNAL_HOSTNAME:-}" ]; then
    PANEL_TYPE="Render"
    PANEL_FAMILY="paas"
elif [ -d "/app" ] && [ -f "/app/Procfile" ] && [ -z "${ORIGINAL_SERVER_PORT}" ] && [ -n "${DYNO:-}" ]; then
    PANEL_TYPE="Heroku-style Dyno"
    PANEL_FAMILY="paas"
elif [ -n "${PUFFER_PORT:-}" ] || [ -n "${PUFFER_SERVER_UUID:-}" ] || grep -qs "pufferpanel" /proc/1/cgroup 2>/dev/null; then
    PANEL_TYPE="PufferPanel"
    PANEL_FAMILY="puffer"
elif [ -n "${FEATHER_PORT:-}" ] || [ -n "${FEATHER_SERVER_ID:-}" ]; then
    PANEL_TYPE="Feather Panel"
    PANEL_FAMILY="feather"
elif [ -n "${P_SERVER_UUID:-}" ] || [ -n "${SERVER_UUID:-}" ] || [ -f "/etc/pterodactyl/config.json" ]; then
    # Wings-family discrimination:
    #   Feather Panel injects P_SERVER_UUID plus a Feather-only short UUID.
    #   Pterodactyl Wings injects SERVER_UUID; Pelican uses P_SERVER_UUID.
    if [ -n "${P_SERVER_UUID_SHORT:-}" ]; then
        PANEL_TYPE="Feather Panel"
        PANEL_FAMILY="feather"
    elif [ -n "${PELICAN_PANEL_VERSION:-}" ] || { [ -n "${P_SERVER_UUID:-}" ] && [ -z "${SERVER_UUID:-}" ]; }; then
        PANEL_TYPE="Pelican Panel"
        PANEL_FAMILY="wings"
    elif [ -n "${JEXACTYL_VERSION:-}" ] || [ -f "/etc/jexactyl/config.json" ]; then
        PANEL_TYPE="Jexactyl"
        PANEL_FAMILY="wings"
    elif [ -n "${WISP_PANEL_VERSION:-}" ] || [ -f "/etc/wisp/config.json" ]; then
        PANEL_TYPE="Wisp"
        PANEL_FAMILY="wings"
    else
        PANEL_TYPE="Pterodactyl Panel"
        PANEL_FAMILY="wings"
    fi
elif [ -n "${EMERALD_SRV_UUID:-}" ]; then
    PANEL_TYPE="Emerald Panel"
    PANEL_FAMILY="wings"
elif [ -n "${HOSTNAME:-}" ] && grep -qs "kubepods" /proc/1/cgroup 2>/dev/null; then
    PANEL_TYPE="Kubernetes Pod"
    PANEL_FAMILY="k8s"
fi

# Cross-panel port compatibility shims for applications that read
# panel-specific port variables. Exported strictly AFTER panel detection -
# exporting them earlier made the Puffer/Feather detection branches always
# match (every container reported PufferPanel).
export FEATHER_PORT="${ACTIVE_PORT}"
export PUFFER_PORT="${ACTIVE_PORT}"

export PANEL_TYPE PANEL_FAMILY

# -----------------------------------------------------------------------------
# 3.2 Architecture & Distro Assurance (works wherever the panel is hosted)
# -----------------------------------------------------------------------------
# * ARCH: exported for all runtime scripts; any CPU (amd64/arm64/armv7/ppc64le/
#   s390x/riscv64/...) proceeds - engines self-check upstream availability.
# * Cross-distro containers: if this egg is run on a foreign base image
#   (alpine yolks, debian slim, fedora, ...), make sure the handful of core
#   tools our launcher needs actually exist. Root gets them installed via the
#   detected package manager; non-root gets a precise, actionable notice.
export ARCH
ARCH="$(uname -m 2>/dev/null || echo unknown)"

ensure_core_tools() {
    local need="" t
    for t in curl tar unzip; do
        command -v "${t}" >/dev/null 2>&1 || need="${need} ${t}"
    done
    command -v jq >/dev/null 2>&1 || need="${need} jq"
    # busybox tar cannot read .tar.xz -> xz binary required on alpine-like bases
    command -v xz >/dev/null 2>&1 || need="${need} xz"
    [ -z "${need}" ] && return 0

    local pkgs="curl tar unzip jq xz ca-certificates bash"
    if [ "$(id -u)" = "0" ]; then
        info "Installing core tools:${need} ..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ${pkgs} >/dev/null 2>&1 || true
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache ${pkgs} >/dev/null 2>&1 || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q ${pkgs} >/dev/null 2>&1 || true
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q ${pkgs} >/dev/null 2>&1 || true
        elif command -v zypper >/dev/null 2>&1; then
            zypper --non-interactive install ${pkgs} >/dev/null 2>&1 || true
        fi
    else
        warn "Base image lacks core tools:${need} and we are non-root, so they cannot be auto-installed."
        warn "Ask your panel admin to pick the official Multi-Language image, or add these packages to a custom image."
        _egg_error_log "entrypoint" "base image lacks core tools:${need}; running as uid $(id -u 2>/dev/null || echo '?') so they cannot be auto-installed"
    fi
}
ensure_core_tools

# -----------------------------------------------------------------------------
# 3.5 Production Reliability: Console Mirroring, Version Stamp, Safety Checks
# -----------------------------------------------------------------------------
# Mirror the entire boot + runtime console into .logs/console.log so users can
# troubleshoot crashes even after the panel scrollback is gone. Opt out with
# LAUNCHER_LOG=0. Rotates the previous boot's log to .1 automatically.
LAUNCH_CONSOLE_LOG=""
if [ "${LAUNCHER_LOG:-1}" = "1" ]; then
    _LOGDIR="${ACTIVE_WORK_DIR}/.logs"
    mkdir -p "${_LOGDIR}" 2>/dev/null || true
    if [ -d "${_LOGDIR}" ] && [ -w "${_LOGDIR}" ]; then
        LAUNCH_CONSOLE_LOG="${_LOGDIR}/console.log"
        [ -f "${LAUNCH_CONSOLE_LOG}" ] && mv -f "${LAUNCH_CONSOLE_LOG}" "${LAUNCH_CONSOLE_LOG}.1" 2>/dev/null || true
        exec > >(tee -a "${LAUNCH_CONSOLE_LOG}") 2>&1
        # Boot header written into the mirror so log segments are easy to tell
        # apart when troubleshooting (panel, arch, uid, timestamp).
        printf '\n=== Prog-Language Eggs boot @ %s | panel=%s | arch=%s | uid=%s ===\n' \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)" \
            "${PANEL_TYPE}" "${ARCH}" "$(id -u 2>/dev/null || echo '?')"
    fi
fi

# Running as root inside a panel container is a security anti-pattern; warn.
if [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
    warn "Container is running as ROOT. Panels should launch images as a non-root user (e.g. uid 988)."
fi

# Image provenance stamp (written at docker build time) for supportability.
if [ -f "/etc/potenfyr-version" ]; then
    info "Image build: $(head -n1 /etc/potenfyr-version 2>/dev/null)"
fi

# -----------------------------------------------------------------------------
# 4. Toolchain & PATH Configuration (Multi-Panel)
# -----------------------------------------------------------------------------
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:${PATH}"
export PATH="${ACTIVE_WORK_DIR}/.runtimes/bin:${ACTIVE_WORK_DIR}/.local/bin:${ACTIVE_WORK_DIR}/bin:${ACTIVE_WORK_DIR}/node_modules/.bin:${ACTIVE_WORK_DIR}/custom/bin:${PATH}"
export PATH="/opt/runtimes/bin:/opt/runtimes/bun/bin:/opt/runtimes/deno/bin:/opt/runtimes/python/bin:/opt/runtimes/zig:/opt/runtimes/dart-sdk/bin:/opt/runtimes/nim/bin:/opt/runtimes/gleam/bin:/opt/runtimes/odin:/opt/runtimes/custom:/opt/runtimes/custom/bin:${PATH}"
export PATH="/root/.cargo/bin:/opt/cargo/bin:${ACTIVE_WORK_DIR}/.cargo/bin:${PATH}"
export PATH="/opt/go/bin:${ACTIVE_WORK_DIR}/go/bin:${PATH}"
export PATH="/opt/dotnet:${ACTIVE_WORK_DIR}/.dotnet:${PATH}"

export GOPATH="${GOPATH:-${ACTIVE_WORK_DIR}/go}"
export CARGO_HOME="${CARGO_HOME:-${ACTIVE_WORK_DIR}/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-/opt/rustup}"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export PYTHONUNBUFFERED=1
export TZ="${TZ:-UTC}"

# Ensure cache directories are writable for rootless / custom UID environments
if [ -w "${ACTIVE_WORK_DIR}" ]; then
    export NPM_CONFIG_CACHE="${ACTIVE_WORK_DIR}/.npm"
    export PIP_CACHE_DIR="${ACTIVE_WORK_DIR}/.cache/pip"
else
    export NPM_CONFIG_CACHE="/tmp/.npm"
    export PIP_CACHE_DIR="/tmp/.cache/pip"
fi

# -----------------------------------------------------------------------------
# 5. Load Persisted Configuration (.multi-prog.conf)
# -----------------------------------------------------------------------------
CONF_FILE="${ACTIVE_WORK_DIR}/.multi-prog.conf"

read_conf() {
    [ -f "${CONF_FILE}" ] || return 1
    local val
    val=$(grep -E "^$1=" "${CONF_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2-)
    [ -n "${val}" ] || return 1
    printf '%s' "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

apply_conf() {
    local key="$1" val
    val=$(read_conf "${key}") || return 0
    if [ -z "${!key-}" ]; then
        eval "export ${key}=\"${val}\"" 2>/dev/null || true
    fi
}

for _key in LANGUAGE RUNNER MAIN_FILE PACKAGE_MANAGER BUILD_COMMAND \
            AUTO_INSTALL_DEPS AUTO_RESTART GIT_REPO GIT_BRANCH \
            GIT_AUTH_TOKEN CUSTOM_COMMAND CUSTOM_RUNTIME_URL EXTRA_ARGS DEBUG RUNTIME_VERSION LANGUAGE_VERSION \
            STARTER_TEMPLATE SERVER_PORT MEMORY_AUTO_TUNE DEV_MODE \
            PRE_RUN_COMMAND POST_RUN_COMMAND CLEAN_BUILD_CACHE AUTO_ENV_INJECT \
            NODE_GYP_SUPPORT EXTRA_RUNTIMES SKIP_RUNTIMES SKIP_PYTHON \
            EGG_UPDATE_URL AUTO_UPDATE_EGG CLI_THEME CLI_BANNER_GRADIENT \
            CUSTOM_INSTALL_COMMAND PANEL_STOP_WATCHER; do
    apply_conf "${_key}"
done
unset _key

# --- Resolved Startup Value Pinning ---------------------------------------------
# The panel cannot be modified from inside the container, so after a boot with
# auto-detection the launcher pins the concrete resolved values (language,
# runner, entry point, runtime version) into .multi-prog.conf. On later boots,
# whenever a startup variable still holds a placeholder (auto / latest /
# default / none / empty), the pinned value wins - the panel Startup tab may
# keep showing "auto", but the exact value chosen on the first boot is reused.
# Setting a variable to the literal value "auto-detect" re-arms detection: the
# pin is cleared and detection runs fresh on this boot.
is_placeholder() {
    case "${1-}" in
        ""|auto|Auto|AUTO|latest|Latest|LATEST|default|Default|none|None) return 0 ;;
        *) return 1 ;;
    esac
}
for _key in LANGUAGE RUNNER MAIN_FILE RUNTIME_VERSION LANGUAGE_VERSION; do
    _eval_cur="\${${_key}-}"
    _cur="$(eval "printf '%s' \"${_eval_cur}\"" 2>/dev/null)"
    case "${_cur}" in
        auto-detect|autodetect|Auto-Detect|AUTO-DETECT)
            # Explicit re-arm: clear the pin, fall back to the neutral default.
            sed -i "/^${_key}=/d" "${CONF_FILE}" 2>/dev/null || true
            case "${_key}" in
                RUNTIME_VERSION|LANGUAGE_VERSION) eval "export ${_key}=latest" ;;
                MAIN_FILE)                        eval "export ${_key}=auto" ;;
                *)                                eval "export ${_key}=auto" ;;
            esac
            ;;
        *)
            _pval="$(read_conf "${_key}" 2>/dev/null || true)"
            if [ -n "${_pval}" ] && is_placeholder "${_cur}"; then
                eval "export ${_key}=\"${_pval}\"" 2>/dev/null || true
            fi
            ;;
    esac
done
unset _key _cur _pval _eval_cur

# -----------------------------------------------------------------------------
# 5.5 Egg Self-Update Engine (EGG_UPDATE_URL)
# -----------------------------------------------------------------------------
# On startup the launcher scripts run from the image; to let users pick up
# launcher fixes without rebuilding/reinstalling the image, EGG_UPDATE_URL can
# point at a run.sh (or egg JSON) on GitHub. Default is this repo's own raw
# egg JSON URL. AUTO_UPDATE_EGG=0 disables the check entirely.
#
# Behaviour:
#   * URL ending in .json / the raw egg file  -> compared against
#     /etc/potenfyr-egg-hash; on change the launcher scripts are refreshed from
#     the same repo branch (egg JSON metadata travels with the image).
#   * URL pointing at a run.sh                -> replaces the launcher directly.
# Failure of any step is non-fatal: the previously installed launcher runs.
phase "Egg Self-Update"
EGG_UPDATE_URL="${EGG_UPDATE_URL:-https://raw.githubusercontent.com/PotenFYR-Studios/Prog-Language-Eggs/main/egg-programming-multi.json}"
AUTO_UPDATE_EGG="${AUTO_UPDATE_EGG:-1}"

# Persist the defaults so servers created before these variables existed get
# them too (they appear in the panel's Startup tab on next boot).
if ! grep -qE '^EGG_UPDATE_URL=' "${CONF_FILE}" 2>/dev/null; then
    printf 'EGG_UPDATE_URL=%s\n' "${EGG_UPDATE_URL}" >> "${CONF_FILE}" 2>/dev/null || true
fi
if ! grep -qE '^AUTO_UPDATE_EGG=' "${CONF_FILE}" 2>/dev/null; then
    printf 'AUTO_UPDATE_EGG=%s\n' "${AUTO_UPDATE_EGG}" >> "${CONF_FILE}" 2>/dev/null || true
fi

if [ "${AUTO_UPDATE_EGG}" = "1" ] && [ -n "${EGG_UPDATE_URL}" ]; then
    if [ -f /usr/local/bin/run.sh ] && command -v curl >/dev/null 2>&1; then
        if [[ "${EGG_UPDATE_URL}" =~ ^https:// ]]; then
            # Non-root panels (uid 988 etc.) cannot write /usr/local/bin; the
            # override lives in /opt/potenfyr - container-local and user-
            # writable, but OUTSIDE the user's data volume so launcher
            # internals are never exposed under /home/container. A workspace
            # path is used only if /opt/potenfyr is not writable (very old
            # images); such copies are migrated back out of the volume by the
            # launcher-resolution step below.
            _egg_target="/usr/local/bin/run.sh"
            _egg_hashfile="/etc/potenfyr-egg-hash"
            _egg_lhash=""
            if ! [ -w "$(dirname "${_egg_target}")" ] || [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
                _egg_state="/opt/potenfyr"
                mkdir -p "${_egg_state}" 2>/dev/null || true
                if ! [ -w "${_egg_state}" ]; then
                    _egg_state="${ACTIVE_WORK_DIR}/.potenfyr"
                fi
                mkdir -p "${_egg_state}" 2>/dev/null || true
                _egg_target="${_egg_state}/run.sh"
                _egg_hashfile="${_egg_state}/egg-hash"
                _egg_lhash="${_egg_state}/launcher-hash"
            fi
            _egg_tmp="$(mktemp 2>/dev/null || echo "/tmp/potenfyr-egg.$$")"
            if curl -fsSL --retry 1 --max-time 15 "${EGG_UPDATE_URL}" -o "${_egg_tmp}" 2>/dev/null && [ -s "${_egg_tmp}" ]; then
                _egg_hash_new="$(sha256sum "${_egg_tmp}" 2>/dev/null | cut -d' ' -f1)"
                _egg_hash_old="$(cat "${_egg_hashfile}" 2>/dev/null || cat /etc/potenfyr-egg-hash 2>/dev/null || true)"
                if [ -n "${_egg_hash_new}" ] && [ "${_egg_hash_new}" != "${_egg_hash_old}" ]; then
                    case "${EGG_UPDATE_URL}" in
                        *.sh)
                            # Direct launcher replacement
                            if cp "${_egg_tmp}" "${_egg_target}" 2>/dev/null; then
                                chmod +x "${_egg_target}" 2>/dev/null || true
                                echo "${_egg_hash_new}" > "${_egg_hashfile}" 2>/dev/null || true
                                [ -n "${_egg_lhash}" ] && sha256sum "${_egg_target}" 2>/dev/null | cut -d' ' -f1 > "${_egg_lhash}" 2>/dev/null || true
                                ok "Launcher self-updated from EGG_UPDATE_URL."
                            else
                                warn "Launcher self-update failed (target not writable): ${_egg_target}"
                            fi
                            ;;
                        *)
                            # egg JSON changed -> refresh launcher from same branch
                            _base="${EGG_UPDATE_URL%/*}"
                            _launcher_ok=0
                            if curl -fsSL --retry 1 --max-time 15 "${_base}/run.sh" -o /tmp/potenfyr-run.sh 2>/dev/null && [ -s /tmp/potenfyr-run.sh ] && grep -q "PotenFYR Studios" /tmp/potenfyr-run.sh 2>/dev/null; then
                                if head -c 2 /tmp/potenfyr-run.sh | grep -q $'\r'; then
                                    sed -i 's/\r$//' /tmp/potenfyr-run.sh 2>/dev/null || true
                                fi
                                if cp /tmp/potenfyr-run.sh "${_egg_target}" 2>/dev/null; then
                                    chmod +x "${_egg_target}" 2>/dev/null || true
                                    _launcher_ok=1
                                fi
                            fi
                            if [ "${_launcher_ok}" = "1" ]; then
                                echo "${_egg_hash_new}" > "${_egg_hashfile}" 2>/dev/null || true
                                [ -n "${_egg_lhash}" ] && sha256sum "${_egg_target}" 2>/dev/null | cut -d' ' -f1 > "${_egg_lhash}" 2>/dev/null || true
                                ok "Egg update detected - launcher refreshed from ${_base}."
                            else
                                warn "Egg update detected but launcher refresh failed - continuing with installed launcher."
                            fi
                            rm -f /tmp/potenfyr-run.sh 2>/dev/null || true
                            ;;
                    esac
                else
                    info "Egg is up to date."
                fi
            else
                warn "EGG_UPDATE_URL fetch failed - continuing with installed launcher."
            fi
            rm -f "${_egg_tmp}" 2>/dev/null || true
            unset _egg_tmp _egg_hash_new _egg_hash_old _egg_target _egg_hashfile _egg_lhash _egg_state _base _launcher_ok
        else
            warn "EGG_UPDATE_URL must be an https:// URL - self-update disabled for safety."
        fi
    fi
fi
# Tell run.sh the check already ran this boot (skips a second network round-trip).
export EGG_UPDATE_CHECKED=1

# -----------------------------------------------------------------------------
# 6. Automatic Memory Tuning & OOM Protection Engine
# -----------------------------------------------------------------------------
phase "Memory Tuning"
MEMORY_AUTO_TUNE="${MEMORY_AUTO_TUNE:-1}"
TOTAL_MEM_MB=0

if [ -n "${SERVER_MEMORY:-}" ] && [[ "${SERVER_MEMORY}" =~ ^[0-9]+$ ]]; then
    TOTAL_MEM_MB="${SERVER_MEMORY}"
elif [ -n "${MEMORY:-}" ] && [[ "${MEMORY}" =~ ^[0-9]+$ ]]; then
    TOTAL_MEM_MB="${MEMORY}"
elif [ -n "${FEATHER_MEMORY:-}" ] && [[ "${FEATHER_MEMORY}" =~ ^[0-9]+$ ]]; then
    TOTAL_MEM_MB="${FEATHER_MEMORY}"
elif [ -n "${PUFFER_MEMORY:-}" ] && [[ "${PUFFER_MEMORY}" =~ ^[0-9]+$ ]]; then
    TOTAL_MEM_MB="${PUFFER_MEMORY}"
fi

if [ "${TOTAL_MEM_MB}" -le 0 ]; then
    if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        CG_BYTES=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "0")
        if [ "${CG_BYTES}" -gt 0 ] && [ "${CG_BYTES}" -lt 9223372036854771712 ]; then
            TOTAL_MEM_MB=$((CG_BYTES / 1024 / 1024))
        fi
    elif [ -f /sys/fs/cgroup/memory.max ]; then
        CG_MAX=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "max")
        if [ "${CG_MAX}" != "max" ] && [ "${CG_MAX}" -gt 0 ]; then
            TOTAL_MEM_MB=$((CG_MAX / 1024 / 1024))
        fi
    fi
fi

SAFE_MEM_MB=0
if [ "${TOTAL_MEM_MB}" -gt 0 ]; then
    SAFE_MEM_MB=$((TOTAL_MEM_MB * 85 / 100))
fi

AUTO_TUNE_INFO="Default"
if [ "${MEMORY_AUTO_TUNE}" = "1" ] && [ "${SAFE_MEM_MB}" -gt 128 ]; then
    AUTO_TUNE_INFO="${SAFE_MEM_MB}MB (${TOTAL_MEM_MB}MB Limit -> 85% Safe Heap)"
    if [[ " ${NODE_OPTIONS:-} " != *"--max-old-space-size"* ]]; then
        export NODE_OPTIONS="--max-old-space-size=${SAFE_MEM_MB} ${NODE_OPTIONS:-}"
    fi

    export GOMEMLIMIT="${SAFE_MEM_MB}MiB"

    export JAVA_AUTO_MEM_FLAGS="-Xmx${SAFE_MEM_MB}M -Xms$((SAFE_MEM_MB / 4))M"
    if [ "${SAFE_MEM_MB}" -ge 4096 ]; then
        export JAVA_AUTO_GC="-XX:+UseZGC"
    elif [ "${SAFE_MEM_MB}" -ge 1024 ]; then
        export JAVA_AUTO_GC="-XX:+UseG1GC"
    else
        export JAVA_AUTO_GC="-XX:+UseSerialGC"
    fi

    export MALLOC_TRIM_THRESHOLD_=100000
    export DOTNET_GCHeapHardLimit="0x$(printf '%X\n' $((SAFE_MEM_MB * 1024 * 1024)))"
fi
export AUTO_TUNE_INFO

# -----------------------------------------------------------------------------
# 7. Automatic .env Network Binding Injector
# -----------------------------------------------------------------------------
AUTO_ENV_INJECT="${AUTO_ENV_INJECT:-1}"
if [ "${AUTO_ENV_INJECT}" = "1" ]; then
    if [ ! -f ".env" ]; then
        cat << EOF > .env
# Auto-generated by PotenFYR Multi-Language Eggs
PORT=${ACTIVE_PORT}
SERVER_PORT=${ACTIVE_PORT}
FEATHER_PORT=${ACTIVE_PORT}
HOST=0.0.0.0
BIND_ADDRESS=0.0.0.0
EOF
    else
        grep -qE "^PORT=" .env && sed -i "s/^PORT=.*/PORT=${ACTIVE_PORT}/" .env || echo "PORT=${ACTIVE_PORT}" >> .env
        grep -qE "^SERVER_PORT=" .env && sed -i "s/^SERVER_PORT=.*/SERVER_PORT=${ACTIVE_PORT}/" .env || echo "SERVER_PORT=${ACTIVE_PORT}" >> .env
        grep -qE "^HOST=" .env || echo "HOST=0.0.0.0" >> .env
    fi
fi

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# 8. Clean, Modern ANSI Gradient Banner & System Information Card
# -----------------------------------------------------------------------------
# Block-font art with a diagonal 256-color gradient sweep. Gradient presets:
#   citrus (brand) aurora sunset ocean candy spectrum | none = flat lime
# CLI_BANNER_GRADIENT picks one; "auto" (default) randomizes per boot.
# Width rules: panel consoles are pipes where tput cannot answer; unknown
# width defaults to 80 so panels get the full gradient block art (the art is
# 70 cols, same footprint as the Database-Eggs banner that renders cleanly).
# The compact fallback only fires on a console that verifiably reports < 74.
print_banner() {
    printf "\n"
    if [ "${CLI_THEME}" = "classic" ]; then
        printf "${C_CYAN}${C_BOLD}%s${C_RESET}\n" "   __  ___      ____  _       __                              "
        printf "${C_CYAN}${C_BOLD}%s${C_RESET}\n" "  /  |/  /_  __/ / /_(_)     / /   ____ _____  ____ _         "
        printf "${C_BLUE}${C_BOLD}%s${C_RESET}\n" " / /|_/ / / / / / __/ /_____/ /   / __ \`/ __ \/ __ \`/         "
        printf "${C_BLUE}${C_BOLD}%s${C_RESET}\n" "/ /  / / /_/ / / /_/ /_____/ /___/ /_/ / / / / /_/ /          "
        printf "${C_MAGENTA}${C_BOLD}%s${C_RESET}\n" "/_/  /_/\\__,_/_/\\__/_/     /_____/\\__,_/_/ /_/\\__, /          "
        printf "${C_MAGENTA}${C_BOLD}%s${C_RESET}\n" "                                             /____/           "
        printf "${C_YELLOW}${C_BOLD}  » Multi-Language Runtime Environment${C_RESET}\n"
        printf "${C_DIM}    By PotenFYR Studios • support@potenfyr.in${C_RESET}\n\n"
        return 0
    fi

    local _gname _ramp=""
    case "${CLI_BANNER_GRADIENT:-auto}" in
        citrus|aurora|sunset|ocean|candy|spectrum) _gname="${CLI_BANNER_GRADIENT}" ;;
        none|off|plain) _gname="none" ;;
        auto|*)
            case $((RANDOM % 6)) in
                0) _gname="citrus" ;;
                1) _gname="aurora" ;;
                2) _gname="sunset" ;;
                3) _gname="ocean" ;;
                4) _gname="candy" ;;
                5) _gname="spectrum" ;;
            esac ;;
    esac
    case "${_gname}" in
        citrus)   _ramp="22 28 34 40 46 82 118 154 190 220 214 208 202" ;;
        aurora)   _ramp="22 28 34 41 47 48 49 50 51 45 39 33 27 21" ;;
        sunset)   _ramp="52 88 124 160 196 202 208 214 220 226" ;;
        ocean)    _ramp="16 17 18 19 20 26 32 38 44 50 51" ;;
        candy)    _ramp="53 91 128 164 200 206 212 218 224 213 177 141 105" ;;
        spectrum) _ramp="196 202 208 214 220 226 190 154 118 82 46 40 34 21 27 33 39 45 51 93 129 165 201 207 213" ;;
    esac

    if [ "${_gname}" != "none" ]; then
        # Print one row, sweeping the ramp across columns with a slight
        # diagonal offset per row so the gradient flows top-left to
        # bottom-right. Spaces pass through uncolored.
        _banner_grad_row() {
            local row="$1" ridx="$2"
            local -a cs
            read -ra cs <<< "${_ramp}"
            local n=${#cs[@]} w=${#row} out="" i ci ch span
            span=$(( (w > 1 ? w : 2) - 1 + 30 ))
            for ((i = 0; i < w; i++)); do
                ch="${row:i:1}"
                if [ "${ch}" = " " ]; then out+=" "; continue; fi
                ci=$(( (i + ridx * 6) * (n - 1) / span ))
                (( ci >= n )) && ci=$(( n - 1 ))
                out+="\e[38;5;${cs[$ci]}m${ch}"
            done
            printf '%b%s\n' "${out}" "${C_RESET}"
        }
        local -a _art=(
' ██████╗██████╗  ██████╗  ██████╗  ██╗      █████╗ ███╗   ██╗ ██████╗ '
'██╔══██╗██╔══██╗██╔═══██╗██╔════╝  ██║     ██╔══██╗████╗  ██║██╔════╝ '
'██████╔╝██████╔╝██║   ██║██║  ███╗ ██║     ███████║██╔██╗ ██║██║  ███╗'
'██╔═══╝ ██╔══██╗██║   ██║██║   ██║ ██║     ██╔══██║██║╚██╗██║██║   ██║'
'██║     ██║  ██║╚██████╔╝╚██████╔╝ ███████╗██║  ██║██║ ╚████║╚██████╔╝'
'╚═╝     ╚═╝  ╚═╝ ╚═════╝  ╚═════╝  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ '
        )
        # Panel daemons attach the console as a PIPE, not a TTY: COLUMNS is
        # unset and tput cannot answer. An unknown width defaults to 80 so
        # panels still get the full gradient art (the 70-col art fits the
        # same panels that render the 72-col Database-Eggs banner cleanly).
        # Only a console that verifiably reports < 74 gets the fallback.
        local _w=""
        _w="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
        case "${_w}" in ""|0|*[!0-9]*) _w=80 ;; esac
        if [ "${_w}" -ge 74 ]; then
            local r
            for r in 0 1 2 3 4 5; do
                _banner_grad_row "${_art[$r]}" "$r"
            done
        else
            # Compact 60-col figlet fallback for narrow/unknown consoles.
            printf "${C_LIME}${C_BOLD}%s${C_GOLD}${C_BOLD}%s${C_RESET}\n" "  ____  ____   ___    ____ " "   _         _     _   _   ____ "
            printf "${C_LIME}${C_BOLD}%s${C_GOLD}${C_BOLD}%s${C_RESET}\n" "|  _ \\|  _ \\  / _ \\  / ___|" "  | |       / \\   | \\ | | / ___|"
            printf "${C_LIME}${C_BOLD}%s${C_GOLD}${C_BOLD}%s${C_RESET}\n" "| |_) || |_) || | | || |  _ " "  | |      / _ \\  |  \\| || |  _ "
            printf "${C_LIME}${C_BOLD}%s${C_GOLD}${C_BOLD}%s${C_RESET}\n" "|  __/ |  __/ | |_| || |_| |" "  | |___  / ___ \\ | |\\  || |_| |"
            printf "${C_LIME}${C_BOLD}%s${C_GOLD}${C_BOLD}%s${C_RESET}\n" "|_|    |_|     \\___/  \\____|" "  |_____|/_/   \\_\\|_| \\_| \\____|"
        fi
    else
        # Flat (CLI_BANNER_GRADIENT=none) - same width rules as above.
        local _w=""
        _w="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
        case "${_w}" in ""|0|*[!0-9]*) _w=80 ;; esac
        if [ "${_w}" -ge 74 ]; then
            printf "${C_LIME}${C_BOLD}  ██████╗ ██████╗  ██████╗ ██████╗   ██╗      █████╗ ███╗   ██╗ ██████╗ ${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}  ██╔══██╗██╔══██╗██╔═══██╗██╔════╝   ██║     ██╔══██╗████╗  ██║██╔════╝ ${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}  ██████╔╝██████╔╝██║   ██║██║  ███╗  ██║     ███████║██╔██╗ ██║██║  ███╗${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}  ██╔═══╝ ██╔══██║██║   ██║██║   ██║  ██║     ██╔══██║██║╚██╗██║██║   ██║${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}  ██║     ██║  ██║╚██████╔╝╚██████╔╝  ███████╗██║  ██║██║ ╚████║╚██████╔╝${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}  ╚═╝     ╚═╝  ╚═╝ ╚═════╝  ╚═════╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ${C_RESET}\n"
        else
            printf "${C_LIME}${C_BOLD}%s${C_RESET}\n" "  ____  ____   ___    ____    _         _     _   _   ____ "
            printf "${C_LIME}${C_BOLD}%s${C_RESET}\n" "|  _ \\|  _ \\  / _ \\  / ___|  | |       / \\   | \\ | | / ___|"
            printf "${C_LIME}${C_BOLD}%s${C_RESET}\n" "| |_) || |_) || | | || |  _   | |      / _ \\  |  \\| || |  _ "
            printf "${C_LIME}${C_BOLD}%s${C_RESET}\n" "|  __/ |  __/ | |_| || |_| |  | |___  / ___ \\ | |\\  || |_| |"
            printf "${C_LIME}${C_BOLD}%s${C_RESET}\n" "|_|    |_|     \\___/  \\____|  |_____|/_/   \\_\\|_| \\_| \\____|"
        fi
    fi

    printf "${C_LIME}${C_BOLD}  </> » Programming Languages · Multi-Language Agent Runtime${C_RESET}\n"
    if [ "${_gname}" = "none" ]; then
        printf "${C_DIM}    By PotenFYR Studios • support@potenfyr.in${C_RESET}\n\n"
    else
        printf "${C_DIM}    By PotenFYR Studios • support@potenfyr.in [%s]${C_RESET}\n\n" "${_gname}"
    fi
}

print_banner
log "Agent boot sequence started — runtime details card follows detection..."

# -----------------------------------------------------------------------------
# 9. Dynamic Toolchain & Auxiliary Runtime Orchestrator (On-Demand)
# -----------------------------------------------------------------------------
phase "Runtime Provisioning"
REQ_LANG="${LANGUAGE:-auto}"
REQ_VER="${RUNTIME_VERSION:-latest}"

if [ "${REQ_LANG}" != "auto" ] && [ "${REQ_LANG}" != "" ] && [ "${REQ_LANG}" != "custom" ]; then
    if [ -f /usr/local/bin/install-runtime.sh ]; then
        /usr/local/bin/install-runtime.sh "${REQ_LANG}" "${REQ_VER}" /opt/runtimes || true
    fi
fi

# Ensure specific engine/runner toolchain is provisioned if chosen (e.g. bun, deno)
if [ "${RUNNER:-auto}" = "bun" ] && ! command -v bun >/dev/null 2>&1; then
    if [ -f /usr/local/bin/install-runtime.sh ]; then
        /usr/local/bin/install-runtime.sh "bun" "latest" /opt/runtimes || true
    fi
elif [ "${RUNNER:-auto}" = "deno" ] && ! command -v deno >/dev/null 2>&1; then
    if [ -f /usr/local/bin/install-runtime.sh ]; then
        /usr/local/bin/install-runtime.sh "deno" "latest" /opt/runtimes || true
    fi
fi

if [ -n "${CUSTOM_RUNTIME_URL:-}" ]; then
    if [ -f /usr/local/bin/install-runtime.sh ]; then
        /usr/local/bin/install-runtime.sh "custom" "${CUSTOM_RUNTIME_URL}" /opt/runtimes || true
    fi
fi

if [ -n "${EXTRA_RUNTIMES:-}" ] && [ "${EXTRA_RUNTIMES}" != "none" ] && [ "${EXTRA_RUNTIMES}" != "auto" ]; then
    # Install companion runtimes in PARALLEL for fast boots; each stream is
    # logged separately to .logs/runtime-install-<name>.log and summarized.
    _LOGDIR="${ACTIVE_WORK_DIR}/.logs"
    mkdir -p "${_LOGDIR}" 2>/dev/null || true
    OLD_IFS="${IFS}"
    IFS=','
    for extra_r in ${EXTRA_RUNTIMES}; do
        IFS="${OLD_IFS}"
        extra_full=$(echo "${extra_r}" | tr -d '[:space:]')
        [ -z "${extra_full}" ] && continue
        # Per-component version syntax: name@version (e.g. python@3.12, java@21)
        extra_r="${extra_full%%@*}"; extra_ver="${extra_full#*@}"
        [ "${extra_ver}" = "${extra_full}" ] && extra_ver="latest"
        extra_r=$(echo "${extra_r}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

        if [ "${SKIP_PYTHON:-0}" = "1" ] && [ "${extra_r}" = "python" ]; then
            continue
        fi

        if [ -f /usr/local/bin/install-runtime.sh ]; then
            log "Installing companion runtime '${extra_r}' (${extra_ver}) in background..."
            (
                if /usr/local/bin/install-runtime.sh "${extra_r}" "${extra_ver}" /opt/runtimes \
                        >>"${_LOGDIR}/runtime-install-${extra_r}.log" 2>&1; then
                    : >"${_LOGDIR}/.${extra_r}.install-ok"
                else
                    : >"${_LOGDIR}/.${extra_r}.install-failed"
                fi
            ) &
        fi
    done
    IFS="${OLD_IFS}"
    wait
    # Summarize parallel install results
    _FAILED=0
    for marker in "${_LOGDIR}"/.*.install-failed; do
        [ -f "${marker}" ] || continue
        _name="$(basename "${marker}" .install-failed)"; _name="${_name#.}"
        warn "Companion runtime '${_name}' FAILED to install -> ${_LOGDIR}/runtime-install-${_name}.log"
        _egg_error_log "entrypoint" "companion runtime install failed: ${_name} - see .logs/runtime-install-${_name}.log"
        rm -f "${marker}"; _FAILED=1
    done
    for marker in "${_LOGDIR}"/.*.install-ok; do
        [ -f "${marker}" ] && rm -f "${marker}"
    done
    [ "${_FAILED}" = "0" ] && ok "All companion runtimes installed successfully."
    unset _FAILED
fi

# -----------------------------------------------------------------------------
# 10. Execute Startup Command
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# 10. Execute Startup Command & Clean User Workspace
# -----------------------------------------------------------------------------
# Clean up any leftover launcher script files so the user directory only
# contains project files. Signature-gated (must contain the studio header),
# so user files with the same name are never touched.
for _egg_script in run.sh entrypoint.sh install.sh install-runtime.sh resolve-version.sh; do
    if [ -f "./${_egg_script}" ] && grep -q "PotenFYR Studios" "./${_egg_script}" 2>/dev/null; then
        rm -f "./${_egg_script}" 2>/dev/null || true
    fi
done
unset _egg_script

phase "Launching Application"
RAW_STARTUP="${STARTUP:-bash /usr/local/bin/run.sh}"

# If startup command is just /entrypoint.sh or empty, default to run.sh
if [ "${RAW_STARTUP}" = "/entrypoint.sh" ] || [ "${RAW_STARTUP}" = "/bin/bash /entrypoint.sh" ] || [ -z "${RAW_STARTUP}" ]; then
    RAW_STARTUP="bash /usr/local/bin/run.sh"
fi

# Replace Pterodactyl variable interpolation {{VAR}} with ${VAR}
MODIFIED_STARTUP=$(echo -e "${RAW_STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

LAUNCHER_SCRIPT="/usr/local/bin/run.sh"
[ ! -f "${LAUNCHER_SCRIPT}" ] && [ -f "/run.sh" ] && LAUNCHER_SCRIPT="/run.sh"

# Launcher state lives OUTSIDE the user's data volume: /opt/potenfyr is
# container-local and user-writable, but never visible under /home/container
# (panel file manager or SFTP). Any legacy workspace copy (.potenfyr/) from
# older egg versions is migrated here when it passes integrity, or discarded
# when it does not - the user volume must never hold executable egg code.
_POT_DIR="/opt/potenfyr"
_LEGACY_POT="${ACTIVE_WORK_DIR}/.potenfyr"
mkdir -p "${_POT_DIR}" 2>/dev/null || true
if [ -d "${_LEGACY_POT}" ]; then
    if [ -f "${_LEGACY_POT}/run.sh" ]; then
        _lh="$(cat "${_LEGACY_POT}/launcher-hash" 2>/dev/null || true)"
        if [ -n "${_lh}" ] && [ "$(sha256sum "${_LEGACY_POT}/run.sh" 2>/dev/null | cut -d' ' -f1)" = "${_lh}" ]; then
            cp "${_LEGACY_POT}/run.sh" "${_POT_DIR}/run.sh" 2>/dev/null || true
            printf '%s\n' "${_lh}" > "${_POT_DIR}/launcher-hash" 2>/dev/null || true
            ok "Launcher override moved out of the user workspace (now /opt/potenfyr)."
        else
            warn "Old .potenfyr launcher override failed integrity check - discarded."
        fi
    fi
    rm -rf "${_LEGACY_POT}" 2>/dev/null || true
fi
unset _LEGACY_POT

# Promote a staged launcher written by the egg self-update engine (run.sh never
# overwrites its own running file) before resolving which launcher to execute.
# The staged copy is only promoted if its recorded sha256 matches, so a user
# cannot plant an arbitrary script and have it executed as PID 1.
if [ -f "${_POT_DIR}/run.sh.update" ] && [ -f "${_POT_DIR}/launcher-hash" ]; then
    _staged_hash="$(sha256sum "${_POT_DIR}/run.sh.update" 2>/dev/null | cut -d' ' -f1)"
    if [ -n "${_staged_hash}" ] && [ "${_staged_hash}" = "$(cat "${_POT_DIR}/launcher-hash" 2>/dev/null)" ]; then
        mv -f "${_POT_DIR}/run.sh.update" "${_POT_DIR}/run.sh" 2>/dev/null || true
    else
        warn "Staged launcher update failed integrity check - discarded."
        rm -f "${_POT_DIR}/run.sh.update" 2>/dev/null || true
    fi
fi
# Prefer a user-space launcher override written by the egg self-update engine
# (EGG_UPDATE_URL) over the image copy - but only after verifying its sha256
# against the hash the engine recorded when it wrote the file (or, for legacy
# overrides, after a branding sanity check). A user-writable file is never
# blindly executed.
if [ -f "${_POT_DIR}/run.sh" ]; then
    _rec_hash="$(cat "${_POT_DIR}/launcher-hash" 2>/dev/null || true)"
    if [ -n "${_rec_hash}" ]; then
        if [ "$(sha256sum "${_POT_DIR}/run.sh" 2>/dev/null | cut -d' ' -f1)" = "${_rec_hash}" ]; then
            LAUNCHER_SCRIPT="${_POT_DIR}/run.sh"
        else
            warn "User-space launcher override failed integrity check - using image launcher."
        fi
    elif grep -q "PotenFYR Studios" "${_POT_DIR}/run.sh" 2>/dev/null; then
        LAUNCHER_SCRIPT="${_POT_DIR}/run.sh"
    else
        warn "Unrecognized launcher override at .potenfyr/run.sh - using image launcher."
    fi
fi
unset _POT_DIR _staged_hash _rec_hash
if [ ! -f "${LAUNCHER_SCRIPT}" ]; then
    mkdir -p /tmp/potenfyr 2>/dev/null || true
    if [ ! -f "/tmp/potenfyr/run.sh" ]; then
        curl -fsSL --retry 3 https://raw.githubusercontent.com/PotenFYR-Studios/Prog-Language-Eggs/main/run.sh -o /tmp/potenfyr/run.sh 2>/dev/null || true
        chmod +x /tmp/potenfyr/run.sh 2>/dev/null || true
    fi
    LAUNCHER_SCRIPT="/tmp/potenfyr/run.sh"
fi

# 1. Normalize any variation of run.sh invocation across old/new/foreign configs.
#    ANY startup that references run.sh is forced to exactly "bash <launcher>":
#    this guarantees bash interpretation (run.sh uses bash features like
#    associative arrays) regardless of whether the old egg wrote sh/bash/./abs
#    paths, and drops stale extra arguments left over from previous eggs.
case "${MODIFIED_STARTUP}" in
    *run.sh*)
        MODIFIED_STARTUP="bash ${LAUNCHER_SCRIPT}"
        ;;
    *)
        # If server was migrated from another egg (e.g. startup was 'node index.js' or 'python main.py'),
        # route it safely through the multi-language launcher as CUSTOM_COMMAND so
        # the user's original command still runs, with all launcher features.
        if [ -n "${MODIFIED_STARTUP}" ] && [ "${MODIFIED_STARTUP}" != "${LAUNCHER_SCRIPT}" ] && [ "${MODIFIED_STARTUP}" != "bash ${LAUNCHER_SCRIPT}" ]; then
            export CUSTOM_COMMAND="${MODIFIED_STARTUP}"
            MODIFIED_STARTUP="bash ${LAUNCHER_SCRIPT}"
        fi
        ;;
esac

# Fallback to /bin/sh if bash is missing on minimal/alpine containers
if ! command -v bash >/dev/null 2>&1; then
    MODIFIED_STARTUP=$(echo "${MODIFIED_STARTUP}" | sed -E 's/\bbash\b/\/bin\/sh/g')
fi

log "Starting application process via launcher..."
printf "%b>>> %s%b\n\n" "${C_DIM}" "${MODIFIED_STARTUP}" "${C_RESET}"

# Execute launcher script replacing entrypoint process (PID 1) for direct signal handling
exec ${MODIFIED_STARTUP}
