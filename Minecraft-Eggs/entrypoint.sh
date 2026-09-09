#!/bin/bash
#
# Multi Minecraft - Universal container entrypoint
#
# Responsibilities:
#   1. Load persisted settings from the server directory (.multi-mc.conf) so
#      choices made in the console survive restarts.
#   2. Detect the hosting panel (Pterodactyl, Pelican, Feather, Jexactyl, Wisp,
#      Emerald, PufferPanel, Kubernetes, plain Docker) and mirror the whole
#      console into .logs/console.log for post-mortem troubleshooting.
#   3. Set a sane base environment (TZ, INTERNAL_IP, umask, no core dumps).
#   4. Automatically select the best available Java runtime for the server
#      (explicit JAVA_VERSION override -> auto-detection by Minecraft version).
#   5. Print the themed gradient banner, then evaluate and execute the STARTUP
#      command provided by the panel (same contract as pterodactyl/yolks).
#
# This image ships Java 8, 11, 17, 21, 25 and 26 side by side so a single
# image can run literally every Minecraft version ever released (Alpha -> 26.x+).
# Future, snapshot, beta, alpha, and obsolete Java versions are also supported
# on-demand via dynamic installation.

# --- Visual theme -------------------------------------------------------------
# Default: PotenFYR agent theme (matches the Prog-Language Eggs console).
# Restore the classic yolk-style theme with CLI_THEME=classic.
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

# Shift out redundant container entrypoint invocations from Docker CMD
while [ $# -gt 0 ]; do
    case "$1" in
        /entrypoint.sh | /usr/local/bin/entrypoint.sh | entrypoint.sh)
            shift
            ;;
        /bin/bash | /usr/bin/bash | bash | /bin/sh | sh)
            if [ "${2:-}" = "/entrypoint.sh" ] || [ "${2:-}" = "/usr/local/bin/entrypoint.sh" ] || [ "${2:-}" = "entrypoint.sh" ]; then
                shift 2
            else
                break
            fi
            ;;
        *)
            break
            ;;
    esac
done

# --- Security baseline ----------------------------------------------------------
# Files created by the entrypoint are group/other-readable but not writable;
# core dumps are disabled so crashes cannot eat server disk space.
umask 022
ulimit -c 0 2>/dev/null || true

# Universal directory detection
if [ -d /home/container ]; then
    cd /home/container 2>/dev/null || true
else
    cd "$(pwd)" 2>/dev/null || true
fi
SERVER_DIR="$(pwd)"
export SERVER_DIR

# --- Error journal ---------------------------------------------------------------
# _egg_error_log(): append-only error journal (egg-level failures only) at
# .logs/launcher-errors.log so failures can be diagnosed after the fact even
# when panel scrollback is gone. Shared with the launcher (run.sh).
ERROR_LOG=""
_egg_error_log() {
    if [ -z "${ERROR_LOG}" ]; then
        local d="${SERVER_DIR:-${PWD}}/.logs"
        if mkdir -p "${d}" 2>/dev/null && [ -w "${d}" ]; then
            ERROR_LOG="${d}/launcher-errors.log"
        else
            ERROR_LOG="/tmp/potenfyr-errors.log"
        fi
    fi
    printf '[%s] [%s] [panel=%s] %s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)" \
        "${1:-egg}" "${PANEL_TYPE:-unknown}" "${2:-unknown error}" \
        >> "${ERROR_LOG}" 2>/dev/null || true
}

# --- Persisted settings ------------------------------------------------------
# .multi-mc.conf is a simple KEY=VALUE file written by the launcher (run.sh)
# whenever the user answers an interactive setup prompt. Values here only fill
# in variables that were NOT provided by the panel, so the panel always wins.
CONF_FILE="${CONF_FILE:-${SERVER_DIR}/.multi-mc.conf}"

read_conf() { # key -> value (safe: no shell evaluation)
    [ -f "${CONF_FILE}" ] || return 1
    local val
    val=$(grep -E "^$1=" "${CONF_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2-)
    [ -n "${val}" ] || return 1
    printf '%s' "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

apply_conf() { # key : only fills in empty/unset environment variables
    local key="$1" val
    val=$(read_conf "${key}") || return 0
    # ${!key} is a safe indirect expansion; values are never evaluated.
    if [ -z "${!key-}" ]; then
        printf -v "${key}" '%s' "${val}"
        export "${key}"
    fi
}

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Cross-panel variable normalization (Pterodactyl, Pelican, Feather, Wisp, Jexactyl, PufferPanel, etc.)
SERVER_PORT="${SERVER_PORT:-${PORT:-${ALLOCATION_PORT:-${SERVER_PORT_0:-25565}}}}"
export SERVER_PORT
SERVER_MEMORY="${SERVER_MEMORY:-${MEMORY:-${MEM_SIZE:-${P_SERVER_MEMORY:-1024}}}}"
export SERVER_MEMORY
SERVER_IP="${SERVER_IP:-${IP:-${P_SERVER_IP:-0.0.0.0}}}"
export SERVER_IP
SERVER_JARFILE="${SERVER_JARFILE:-${JARFILE:-server.jar}}"
export SERVER_JARFILE

# Set environment variable that holds the Internal Docker IP. Images without
# the iproute2 `ip` binary (slim images) fall back to hostname -I, then to the
# panel-provided SERVER_IP, then 0.0.0.0.
if command -v ip >/dev/null 2>&1; then
    INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')
elif command -v hostname >/dev/null 2>&1; then
    INTERNAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
INTERNAL_IP="${INTERNAL_IP:-${SERVER_IP:-0.0.0.0}}"
export INTERNAL_IP

# Load persisted settings for anything the panel did not provide.
for _key in SERVER_TYPE MINECRAFT_VERSION BUILD_NUMBER LOADER_VERSION \
            SERVER_JARFILE JAVA_VERSION JAVA_FLAGS GC_TYPE MOTD MAX_PLAYERS \
            EXTRA_ARGS CUSTOM_COMMAND AUTO_UPDATE KEEP_BACKUP DEBUG \
            GITHUB_REPO GITHUB_TAG GITHUB_ASSET \
            EGG_UPDATE_URL AUTO_UPDATE_EGG \
            CLI_THEME CLI_BANNER_GRADIENT PANEL_STOP_WATCHER; do
    apply_conf "${_key}"
done
unset _key val

# --- Console theme ---------------------------------------------------------------
# Defined AFTER the persisted-settings loop above so CLI_THEME from
# .multi-mc.conf (servers older than the theme variables) applies too.
if [ "${CLI_THEME}" = "classic" ]; then
    log()   { printf "%b %b\n" "${C_CYAN}${C_BOLD}[PotenFYR]${C_RESET}" "$*"; }
    ok()    { printf "%b %b\n" "${C_GREEN}${C_BOLD}[PotenFYR][✓]${C_RESET}" "$*"; }
    warn()  { printf "%b %b\n" "${C_YELLOW}${C_BOLD}[PotenFYR][!]${C_RESET}" "${C_YELLOW}$*${C_RESET}"; }
    error() { printf "%b %b\n" "${C_RED}${C_BOLD}[PotenFYR][✗]${C_RESET}" "${C_RED}$*${C_RESET}"; _egg_error_log "entrypoint" "$*"; }
    info()  { printf "%b %b\n" "${C_BLUE}${C_BOLD}[PotenFYR][i]${C_RESET}" "$*"; }
else
    log()   { printf "%b %b\n" "${C_LIME}${C_BOLD}</> multi-minecraft${C_RESET}${C_DIM} ▸${C_RESET}" "$*"; }
    ok()    { printf "%b %b\n" "${C_LIME}${C_BOLD}</> multi-minecraft ✔${C_RESET}" "${C_GREEN}$*${C_RESET}"; }
    warn()  { printf "%b %b\n" "${C_GOLD}${C_BOLD}</> multi-minecraft ⚠${C_RESET}" "${C_YELLOW}$*${C_RESET}"; }
    error() { printf "%b %b\n" "${C_RED}${C_BOLD}</> multi-minecraft ✖${C_RESET}" "${C_RED}$*${C_RESET}"; _egg_error_log "entrypoint" "$*"; }
    info()  { printf "%b %b\n" "${C_CYAN}${C_BOLD}</> multi-minecraft ℹ${C_RESET}" "$*"; }
fi

phase() { printf "\n%b── %s %b\n" "${C_DIM}" "$*" "────────────────────────────────────────────────${C_RESET}"; }

# Ensure /usr/local/bin is in PATH (internal scripts live in the image, keeping server dir clean)
export PATH="/usr/local/bin:${PATH}"
# Remove stale copies of OUR launcher scripts from the server directory (older
# egg versions dropped them there) - user files with the same name are kept.
if [ -f ./run.sh ] && grep -q "Multi Minecraft" ./run.sh 2>/dev/null; then
    rm -f ./run.sh 2>/dev/null || true
fi
if [ -f ./install.sh ] && grep -q "Multi Minecraft" ./install.sh 2>/dev/null; then
    rm -f ./install.sh 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Multi-panel host detection (accurate, multi-panel, multi-platform)
# ---------------------------------------------------------------------------
# Detection strategy (most specific -> most generic), exporting both a human
# label and a machine family so launchers can adapt behaviour per platform:
#
#   FAMILY wings    : Pterodactyl, Pelican, Jexactyl, Wisp, Emerald (Wings-based)
#   FAMILY feather  : Feather Panel
#   FAMILY puffer   : PufferPanel
#   FAMILY k8s      : Kubernetes / OpenShift / Nomad orchestrators
#   FAMILY docker   : Plain Docker / Podman / containerd
PANEL_TYPE="Docker / Standalone"
PANEL_FAMILY="docker"

if [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
    PANEL_TYPE="Kubernetes Pod"
    PANEL_FAMILY="k8s"
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
export PANEL_TYPE PANEL_FAMILY

# --- Console mirror --------------------------------------------------------------
# Mirror the entire boot + runtime console into .logs/console.log so users can
# troubleshoot crashes even after the panel scrollback is gone. Opt out with
# LAUNCHER_LOG=0. Rotates the previous boot's log to .1 automatically.
if [ "${LAUNCHER_LOG:-1}" = "1" ]; then
    _LOGDIR="${SERVER_DIR}/.logs"
    mkdir -p "${_LOGDIR}" 2>/dev/null || true
    if [ -d "${_LOGDIR}" ] && [ -w "${_LOGDIR}" ]; then
        LAUNCH_CONSOLE_LOG="${_LOGDIR}/console.log"
        [ -f "${LAUNCH_CONSOLE_LOG}" ] && mv -f "${LAUNCH_CONSOLE_LOG}" "${LAUNCH_CONSOLE_LOG}.1" 2>/dev/null || true
        exec > >(tee -a "${LAUNCH_CONSOLE_LOG}") 2>&1
        # Boot header written into the mirror so log segments are easy to tell
        # apart when troubleshooting (panel, arch, uid, timestamp).
        printf '\n=== Multi Minecraft boot @ %s | panel=%s | arch=%s | uid=%s ===\n' \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)" \
            "${PANEL_TYPE}" "$(uname -m 2>/dev/null || echo unknown)" "$(id -u 2>/dev/null || echo '?')"
    fi
fi
unset LAUNCH_CONSOLE_LOG

# Running as root inside a panel container is a security anti-pattern; warn.
if [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
    warn "Container is running as ROOT. Panels should launch images as a non-root user (e.g. uid 988)."
fi

# Image provenance stamp (written at docker build time) for supportability.
if [ -f "/etc/potenfyr-version" ]; then
    info "Image build: $(head -n1 /etc/potenfyr-version 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# Egg Self-Update Engine (EGG_UPDATE_URL)

# ---------------------------------------------------------------------------
# Egg Self-Update Engine (EGG_UPDATE_URL)
# ---------------------------------------------------------------------------
# Launcher scripts ship inside the image; EGG_UPDATE_URL lets users pick up
# launcher fixes without rebuilding/reinstalling. Default points at this
# repo's own raw egg JSON. AUTO_UPDATE_EGG=0 disables the check entirely.
#
# Behaviour (same as the programming eggs):
#   * HTTPS-only: plain-http update URLs are rejected (tampered downloads).
#   * URL ending in .json / the raw egg file -> compared against the stored
#     hash; on change the launcher scripts are refreshed from the same repo
#     branch. The refreshed launcher's own sha256 is recorded and verified
#     before it is ever executed.
#   * URL pointing at a run.sh -> replaces the launcher directly.
# Failure of any step is non-fatal: the previously installed launcher runs.
phase "Egg Self-Update"
EGG_UPDATE_URL="${EGG_UPDATE_URL:-https://raw.githubusercontent.com/PotenFYR-Studios/Minecraft-Eggs/main/egg-minecraft-multi.json}"
AUTO_UPDATE_EGG="${AUTO_UPDATE_EGG:-1}"

# Persist the defaults so servers created before these variables existed get
# them too (they appear in the panel's Startup tab on next boot).
if ! grep -qE '^CLI_THEME=' "${CONF_FILE}" 2>/dev/null; then
    printf 'CLI_THEME=%s\n' "${CLI_THEME}" >> "${CONF_FILE}" 2>/dev/null || true
fi
if ! grep -qE '^CLI_BANNER_GRADIENT=' "${CONF_FILE}" 2>/dev/null; then
    printf 'CLI_BANNER_GRADIENT=auto\n' >> "${CONF_FILE}" 2>/dev/null || true
fi
if ! grep -qE '^PANEL_STOP_WATCHER=' "${CONF_FILE}" 2>/dev/null; then
    printf 'PANEL_STOP_WATCHER=auto\n' >> "${CONF_FILE}" 2>/dev/null || true
fi

if [ "${AUTO_UPDATE_EGG}" = "1" ] && [ -n "${EGG_UPDATE_URL}" ] && [ -f /opt/potenfyr/run.sh ] && command -v curl >/dev/null 2>&1; then
    if echo "${EGG_UPDATE_URL}" | grep -q '^https://'; then
        # Canonical egg scripts live root-owned in /opt/potenfyr; only root
        # can write there. Non-root panels (uid 988 etc.) fall back to a
        # user-writable override location that launcher resolution below
        # prefers over the image copy - after hash verification.
        _egg_target="/opt/potenfyr/run.sh"
        _egg_hashfile="/etc/potenfyr-egg-hash"
        _egg_lhash="/etc/potenfyr-launcher-hash"
        if ! [ -w "$(dirname "${_egg_target}")" ] || [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
            _egg_target="${SERVER_DIR}/.potenfyr/run.sh"
            _egg_hashfile="${SERVER_DIR}/.potenfyr/egg-hash"
            _egg_lhash="${SERVER_DIR}/.potenfyr/launcher-hash"
            mkdir -p "${SERVER_DIR}/.potenfyr" 2>/dev/null || true
        fi
        _egg_tmp="$(mktemp 2>/dev/null || echo "/tmp/potenfyr-egg.$$")"
        # --proto-redir '=https' keeps the https-only guarantee across redirects:
        # a URL that 3xx-redirects to plain http is refused instead of downloaded
        # in cleartext.
        if curl -fsSL --proto '=https' --proto-redir '=https' --retry 2 --max-time 30 "${EGG_UPDATE_URL}" -o "${_egg_tmp}" 2>/dev/null && [ -s "${_egg_tmp}" ]; then
            _egg_hash_new="$(sha256sum "${_egg_tmp}" 2>/dev/null | cut -d' ' -f1)"
            _egg_hash_old="$(cat "${_egg_hashfile}" 2>/dev/null || cat /etc/potenfyr-egg-hash 2>/dev/null || true)"
            if [ -n "${_egg_hash_new}" ] && [ "${_egg_hash_new}" != "${_egg_hash_old}" ]; then
                case "${EGG_UPDATE_URL}" in
                    *.sh)
                        # Direct launcher replacement
                        if cp "${_egg_tmp}" "${_egg_target}" 2>/dev/null; then
                            chmod +x "${_egg_target}" 2>/dev/null || true
                            echo "${_egg_hash_new}" > "${_egg_hashfile}" 2>/dev/null || true
                            sha256sum "${_egg_target}" 2>/dev/null | cut -d' ' -f1 > "${_egg_lhash}" 2>/dev/null || true
                            ok "Launcher self-updated from EGG_UPDATE_URL."
                        else
                            warn "Launcher self-update failed (target not writable): ${_egg_target}"
                        fi
                        ;;
                    *)
                        # egg JSON changed -> refresh launcher from same branch
                        _egg_base="${EGG_UPDATE_URL%/*}"
                        _egg_launcher_ok=0
                        if curl -fsSL --proto '=https' --proto-redir '=https' --retry 2 --max-time 30 "${_egg_base}/run.sh" -o /tmp/potenfyr-run.sh 2>/dev/null && [ -s /tmp/potenfyr-run.sh ] && grep -q "Multi Minecraft" /tmp/potenfyr-run.sh 2>/dev/null; then
                            if head -c 2 /tmp/potenfyr-run.sh | grep -q $'\r'; then
                                sed -i 's/\r$//' /tmp/potenfyr-run.sh 2>/dev/null || true
                            fi
                            if cp /tmp/potenfyr-run.sh "${_egg_target}" 2>/dev/null; then
                                chmod +x "${_egg_target}" 2>/dev/null || true
                                sha256sum "${_egg_target}" 2>/dev/null | cut -d' ' -f1 > "${_egg_lhash}" 2>/dev/null || true
                                _egg_launcher_ok=1
                            fi
                        fi
                        if [ "${_egg_launcher_ok}" = "1" ]; then
                            echo "${_egg_hash_new}" > "${_egg_hashfile}" 2>/dev/null || true
                            ok "Egg update detected - launcher refreshed from ${_egg_base}."
                        else
                            warn "Egg update detected but launcher refresh failed - continuing with installed launcher."
                        fi
                        rm -f /tmp/potenfyr-run.sh 2>/dev/null || true
                        ;;
                esac
            else
                info "Egg is up to date."
            fi
            rm -f "${_egg_tmp}" 2>/dev/null || true
            unset _egg_tmp _egg_hash_new _egg_hash_old _egg_target _egg_hashfile _egg_lhash _egg_base _egg_launcher_ok
        else
            warn "EGG_UPDATE_URL fetch failed - continuing with installed launcher."
            rm -f "${_egg_tmp}" 2>/dev/null || true
            unset _egg_tmp
        fi
    else
        warn "EGG_UPDATE_URL must be an https:// URL - self-update disabled for safety."
    fi
fi
# Tell run.sh the check already ran this boot (skips a second network round-trip).
export EGG_UPDATE_CHECKED=1

if [ "${DEBUG:-0}" = "1" ]; then
    warn "DEBUG mode enabled - printing resolved environment (secrets excluded):"
    env | grep -E '^(SERVER_|MINECRAFT|BUILD_|LOADER_|JAVA_|GC_|EXTRA_|CUSTOM_|AUTO_|KEEP_|MOTD|MAX_|ONLINE_|VIEW_|DIFFICULTY|GAMEMODE|PVP|GITHUB_|CLI_|PANEL_STOP|PANEL_|DEBUG|TZ|INTERNAL_IP)' | sort
fi

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Java runtime auto-selection
# ---------------------------------------------------------------------------
# Selects the best Java runtime home directory for the server.
phase "Runtime Provisioning"
detect_java_home() {
    local type="${SERVER_TYPE:-vanilla}"
    local mc="${MINECRAFT_VERSION:-latest}"
    local v=""

    type=$(echo "${type}" | tr '[:upper:]' '[:lower:]')

    # Non-Java server types don't need a JVM.
    case "${type}" in
        bedrock | pocketmine)
            echo ""
            return
            ;;
    esac

    # 1. Custom Java direct URL via JAVA_URL environment variable
    if [ -n "${JAVA_URL:-}" ]; then
        log "Custom Java URL specified (${JAVA_URL}); downloading runtime..."
        install-java.sh "${JAVA_URL}" "custom" >&2 || true
        for cand in "/opt/java/custom" "${SERVER_DIR}/java" "${SERVER_DIR}/jre" "${SERVER_DIR}/jdk" "${HOME}/.java/custom" "/home/container/.java/custom"; do
            if [ -x "${cand}/bin/java" ]; then
                echo "${cand}"
                return
            fi
        done
    fi

    # 2. Custom Java via JAVA_VERSION (URL, vendor, local keyword, or explicit version)
    if [ -n "${JAVA_VERSION:-}" ]; then
        # Direct URL in JAVA_VERSION
        if [[ "${JAVA_VERSION}" =~ ^https?:// ]]; then
            log "Custom Java URL provided in JAVA_VERSION; downloading..."
            install-java.sh "${JAVA_VERSION}" "custom" >&2 || true
            for cand in "/opt/java/custom" "${SERVER_DIR}/java" "${SERVER_DIR}/jre" "${SERVER_DIR}/jdk" "${HOME}/.java/custom" "/home/container/.java/custom"; do
                if [ -x "${cand}/bin/java" ]; then
                    echo "${cand}"
                    return
                fi
            done
        fi

        # Local directory check if requested (custom, local, or directory name)
        case "${JAVA_VERSION}" in
            custom | local | self | manual)
                for cand in "${SERVER_DIR}/java" "${SERVER_DIR}/jre" "${SERVER_DIR}/jdk" "./java" "./jre" "./jdk" "/home/container/java" "/home/container/jre" "/home/container/jdk" "/opt/java/custom" "${HOME}/.java/custom"; do
                    if [ -x "${cand}/bin/java" ]; then
                        echo "${cand}"
                        return
                    fi
                done
                ;;
        esac

        # Check pre-installed path
        for cand in "/opt/java/${JAVA_VERSION}" "${HOME}/.java/${JAVA_VERSION}" "${SERVER_DIR}/.java/${JAVA_VERSION}" "/home/container/.java/${JAVA_VERSION}"; do
            if [ -x "${cand}/bin/java" ]; then
                echo "${cand}"
                return
            fi
        done

        # If not present, download on-demand (e.g. graalvm-21, corretto-21, 27, 28)
        if command -v install-java.sh >/dev/null 2>&1; then
            log "Java runtime '${JAVA_VERSION}' requested but not present; downloading..."
            install-java.sh "${JAVA_VERSION}" >&2 || true
            for cand in "/opt/java/${JAVA_VERSION}" "${HOME}/.java/${JAVA_VERSION}" "/home/container/.java/${JAVA_VERSION}"; do
                if [ -x "${cand}/bin/java" ]; then
                    echo "${cand}"
                    return
                fi
            done
        fi
    fi

    # 3. Check for local custom JVM bundled in the server directory
    for cand in "./java" "./jre" "./jdk" "/home/container/java" "/home/container/jre" "/home/container/jdk"; do
        if [ -x "${cand}/bin/java" ]; then
            log "Detected local custom Java runtime at ${cand}"
            echo "${cand}"
            return
        fi
    done

    # 4. Proxies / standalone Java applications use their own versioning scheme.
    case "${type}" in
        velocity | waterfall | bungeecord | nukkit | sponge* | glowstone | cuberite)
            for cand in "/opt/java/21" "${HOME}/.java/21"; do
                if [ -x "${cand}/bin/java" ]; then
                    echo "${cand}"
                    return
                fi
            done
            ;;
    esac

    # 5. Map Minecraft versions to their required Java generation:
    #   Future 27.x+     -> Java 27+
    #   26.x / 26w*      -> Java 26
    #   20.x - 25.x      -> Java 25
    #   1.20.5 - 1.21.x  -> Java 21
    #   1.17 - 1.20.4    -> Java 17
    #   anything older   -> Java 8 (including Alpha, Beta, Classic, InDev, Infdev)
    case "${mc}" in
        latest | latest-snapshot)
            v="21"
            ;;
        [3-9][0-9].* | 2[7-9].*)
            v=$(echo "${mc}" | cut -d. -f1)
            ;;
        26.* | 2[6-9]w*)
            v="26"
            ;;
        2[0-5].* | 25w*)
            v="25"
            ;;
        24w*)
            v="21"
            ;;
        20w4[5-9]* | 20w5* | 2[1-3]w*)
            v="17"
            ;;
        1.20.[5-9]* | 1.2[1-9]*)
            v="21"
            ;;
        1.17* | 1.18* | 1.19* | 1.20 | 1.20.[1-4]*)
            v="17"
            ;;
        a1.* | b1.* | c0.* | in-* | rd-* | inf-* | 1.1[0-6]* | 1.[0-9]*)
            v="8"
            ;;
        *)
            v="21"
            ;;
    esac

    # 1. Check if target runtime is installed
    for cand in "/opt/java/${v}" "${HOME}/.java/${v}" "${SERVER_DIR}/.java/${v}"; do
        if [ -x "${cand}/bin/java" ]; then
            echo "${cand}"
            return
        fi
    done

    # 2. Fall back to newest runtime already pre-installed in /opt/java or ~/.java
    local dir
    for dir in "/opt/java" "${HOME}/.java"; do
        if [ -d "${dir}" ]; then
            for cand in $(find "${dir}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V -r); do
                if [ -x "${dir}/${cand}/bin/java" ]; then
                    echo "${dir}/${cand}"
                    return
                fi
            done
        fi
    done

    # 3. Attempt on-demand download if missing
    if command -v install-java.sh >/dev/null 2>&1; then
        install-java.sh "${v}" >&2 2>/dev/null || true
        for cand in "/opt/java/${v}" "${HOME}/.java/${v}"; do
            if [ -x "${cand}/bin/java" ]; then
                echo "${cand}"
                return
            fi
        done
    fi

    echo ""
}

RESOLVED_JAVA_HOME="$(detect_java_home)"
if [ -n "${RESOLVED_JAVA_HOME}" ] && [ -x "${RESOLVED_JAVA_HOME}/bin/java" ]; then
    export JAVA_HOME="${RESOLVED_JAVA_HOME}"
    export PATH="${JAVA_HOME}/bin:${PATH}"
    JAVA_SELECTED="$(basename "${JAVA_HOME}")"
else
    JAVA_SELECTED=""
fi

# -----------------------------------------------------------------------------
# Startup banner (PLE theme engine: dense block art + diagonal gradient)
# -----------------------------------------------------------------------------
# "MULTI MC" in the ANSI Shadow block font (62 cols, 6 rows, programmatically
# aligned) with a diagonal 256-color gradient sweep - the same look as the
# Prog-Language-Eggs banner. Gradient presets:
#   citrus (brand) aurora sunset ocean candy spectrum | none = flat brand color
# CLI_BANNER_GRADIENT picks one; "auto" (default) randomizes per boot.
# Narrow consoles fall back to the compact-slant art, then to plain text.
print_banner() {
    printf "\n"
    if [ "${CLI_THEME}" = "classic" ]; then
        printf "${C_CYAN}${C_BOLD}   __  ___      ____  _       __  ___     ${C_RESET}\n"
        printf "${C_CYAN}${C_BOLD}  /  |/  /_  __/ / /_(_)     /  |/  /____ ${C_RESET}\n"
        printf "${C_BLUE}${C_BOLD} / /|_/ / / / / / __/ /_____/ /|_/ / ___/ ${C_RESET}\n"
        printf "${C_BLUE}${C_BOLD}/ /  / / /_/ / / /_/ /_____/ /  / / /__   ${C_RESET}\n"
        printf "${C_MAGENTA}${C_BOLD}/_/  /_/\\__,_/_/\\__/_/     /_/  /_/\\___/   ${C_RESET}\n"
        printf "${C_YELLOW}${C_BOLD}  » Universal Minecraft Server Runtime${C_RESET}\n"
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
        # bottom-right. Spaces pass through uncolored. The real ESC byte is
        # concatenated (not a "\e" sequence re-interpreted by printf %b):
        # %b re-processing would double-escape the art's backslashes and
        # print literal "\e" artifacts in rows containing "\_" (row 5).
        local _esc=$'\033'
        _banner_grad_row() {
            local row="$1" ridx="$2"
            local -a cs
            read -ra cs <<< "${_ramp}"
            local n=${#cs[@]} w=${#row} out="" i ci ch span
            span=$(( (w > 1 ? w : 2) - 1 + 24 ))
            for ((i = 0; i < w; i++)); do
                ch="${row:i:1}"
                if [ "${ch}" = " " ]; then out+=" "; continue; fi
                ci=$(( (i + ridx * 5) * (n - 1) / span ))
                (( ci >= n )) && ci=$(( n - 1 ))
                out+="${_esc}[38;5;${cs[$ci]}m${ch}"
            done
            printf '%s%s\n' "${out}" "${C_RESET}"
        }
        local -a _art_block=(
'███╗   ███╗██╗   ██╗██╗  ████████╗██╗    ███╗   ███╗ ██████╗'
'████╗ ████║██║   ██║██║  ╚══██╔══╝██║    ████╗ ████║██╔════╝'
'██╔████╔██║██║   ██║██║     ██║   ██║    ██╔████╔██║██║     '
'██║╚██╔╝██║██║   ██║██║     ██║   ██║    ██║╚██╔╝██║██║     '
'██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║    ██║ ╚═╝ ██║╚██████╗'
'╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝    ╚═╝     ╚═╝ ╚═════╝'
        )
        local -a _art_slim=(
'   __  ___      ____  _       __  ___    '
'  /  |/  /_  __/ / /_(_)     /  |/  /____ '
' / /|_/ / / / / / __/ /_____/ /|_/ / ___/ '
'/ /  / / /_/ / / /_/ /_____/ /  / / /__   '
'/_/  /_/\__,_/_/\__/_/     /_/  /_/\___/   '
        )
        local _w r
        _w="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
        _w="${_w:-80}"
        if [ "${_w}" -ge 64 ] 2>/dev/null; then
            for r in 0 1 2 3 4 5; do
                _banner_grad_row "${_art_block[$r]}" "$r"
            done
        elif [ "${_w}" -ge 46 ] 2>/dev/null; then
            for r in 0 1 2 3 4; do
                _banner_grad_row "${_art_slim[$r]}" "$r"
            done
        else
            # Ultra-narrow fallback: plain text, still themed.
            printf "${C_LIME}${C_BOLD}  MULTI MINECRAFT${C_RESET}\n"
        fi
    else
        if [ "${_w:-80}" -ge 64 ] 2>/dev/null; then
            printf "${C_LIME}${C_BOLD}███╗   ███╗██╗   ██╗██╗  ████████╗██╗    ███╗   ███╗ ██████╗${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}████╗ ████║██║   ██║██║  ╚══██╔══╝██║    ████╗ ████║██╔════╝${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}██╔████╔██║██║   ██║██║     ██║   ██║    ██╔████╔██║██║     ${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}██║╚██╔╝██║██║   ██║██║     ██║   ██║    ██║╚██╔╝██║██║     ${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}██║ ╚═╝ ██║╚██████╔╝███████╗██║   ██║    ██║ ╚═╝ ██║╚██████╗${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚═╝    ╚═╝     ╚═╝ ╚═════╝${C_RESET}\n"
        else
            printf "${C_LIME}${C_BOLD}   __  ___      ____  _       __  ___     ${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}  /  |/  /_  __/ / /_(_)     /  |/  /____ ${C_RESET}\n"
            printf "${C_LIME}${C_BOLD} / /|_/ / / / / / __/ /_____/ /|_/ / ___/ ${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}/ /  / / /_/ / / /_/ /_____/ /  / / /__   ${C_RESET}\n"
            printf "${C_LIME}${C_BOLD}/_/  /_/\__,_/_/\__/_/     /_/  /_/\___/   ${C_RESET}\n"
        fi
    fi

    printf "${C_LIME}${C_BOLD}  » Universal Minecraft Server Runtime${C_RESET}\n"
    if [ "${_gname}" = "none" ]; then
        printf "${C_DIM}    By PotenFYR Studios • support@potenfyr.in${C_RESET}\n\n"
    else
        printf "${C_DIM}    By PotenFYR Studios • support@potenfyr.in · gradient: %s${C_RESET}\n\n" "${_gname}"
    fi
}

print_banner

log "Multi Minecraft boot sequence started — runtime details card follows in the launcher..."

# ---------------------------------------------------------------------------
# Startup command evaluation (yolks-compatible)
# ---------------------------------------------------------------------------
phase "Launching Application"
CMD_TO_RUN="${STARTUP:-}"
if [ -z "${CMD_TO_RUN}" ] && [ $# -gt 0 ]; then
    CMD_TO_RUN="$*"
fi
[ -z "${CMD_TO_RUN}" ] && CMD_TO_RUN="run.sh"

# Convert all of the "{{VARIABLE}}" parts of the command into the expected
# shell variable format of "${VARIABLE}" before evaluating the string.
PARSED="${CMD_TO_RUN}"
PARSED=$(echo "${PARSED}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
PARSED=$(eval echo "\"${PARSED}\"")

# Promote a staged launcher written by the egg self-update engine before
# resolving which launcher to execute. The staged copy is only promoted if its
# recorded sha256 matches; the override is only ever executed when its sha256
# matches the hash recorded at download time.
_POT_DIR="${SERVER_DIR}/.potenfyr"
if [ -f "${_POT_DIR}/run.sh.update" ] && [ -f "${_POT_DIR}/launcher-hash" ]; then
    _staged_hash="$(sha256sum "${_POT_DIR}/run.sh.update" 2>/dev/null | cut -d' ' -f1)"
    if [ -n "${_staged_hash}" ] && [ "${_staged_hash}" = "$(cat "${_POT_DIR}/launcher-hash" 2>/dev/null)" ]; then
        mv -f "${_POT_DIR}/run.sh.update" "${_POT_DIR}/run.sh" 2>/dev/null || true
    else
        warn "Staged launcher update failed integrity check - discarded."
        rm -f "${_POT_DIR}/run.sh.update" 2>/dev/null || true
    fi
fi
unset _staged_hash

# Normalize any run.sh execution variants (old and new panel formats) to the
# internal binary. A user-space launcher override written by the egg
# self-update engine (EGG_UPDATE_URL) is preferred over the image copy - but
# ONLY when its sha256 matches the hash recorded by the update engine in the
# same write transaction. Override files without a recorded hash (or with a
# mismatching hash) are never executed: a user-writable file is not trusted
# just because it contains a branding string.
case "${PARSED}" in
    "bash run.sh" | "run.sh" | "./run.sh" | "bash ./run.sh" | "/run.sh" | "bash /run.sh" | "/usr/local/bin/run.sh" | "bash /usr/local/bin/run.sh" | "/opt/potenfyr/run.sh" | "bash /opt/potenfyr/run.sh" | "")
        LAUNCHER_SCRIPT="/opt/potenfyr/run.sh"
        if [ -f "${_POT_DIR}/run.sh" ]; then
            _rec_hash="$(cat "${_POT_DIR}/launcher-hash" 2>/dev/null || true)"
            if [ -n "${_rec_hash}" ] && [ "$(sha256sum "${_POT_DIR}/run.sh" 2>/dev/null | cut -d' ' -f1)" = "${_rec_hash}" ]; then
                LAUNCHER_SCRIPT="${_POT_DIR}/run.sh"
            else
                warn "User-space launcher override failed integrity check - using image launcher."
                rm -f "${_POT_DIR}/run.sh" 2>/dev/null || true
            fi
        fi
        PARSED="${LAUNCHER_SCRIPT}"
        unset _POT_DIR _rec_hash
        ;;
esac

# If the command directly calls java and server files are missing, run installer first
if echo "${PARSED}" | grep -q "java " && [ ! -f "${SERVER_JARFILE:-server.jar}" ] && [ ! -f unix_args.txt ]; then
    log "Server files not found. Running automatic installation before starting..."
    if [ -x /opt/potenfyr/install.sh ]; then
        bash /opt/potenfyr/install.sh || warn "Automatic install exited with code $?"
    elif [ -x /usr/local/bin/install.sh ]; then
        bash /usr/local/bin/install.sh || warn "Automatic install exited with code $?"
    elif [ -x /install.sh ]; then
        bash /install.sh || warn "Automatic install exited with code $?"
    fi
fi

log "Starting server via launcher..."
printf "%b>>> %s%b\n\n" "${C_DIM}" "${PARSED}" "${C_RESET}"
# Use 'exec' inside bash -c so the server (via run.sh) becomes PID 1 and
# receives SIGTERM/SIGINT directly. Without the inner exec, PID 1 would
# remain a shell that does not forward signals, causing stop/restart to hang
# until the panel force-kills the container.
exec bash -c "exec ${PARSED}"
