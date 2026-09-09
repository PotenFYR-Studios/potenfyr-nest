#!/bin/bash
# =============================================================================
#  Multi Minecraft - Universal Installation Script
#
#  Runs inside the universal image (ghcr.io/potenfyr-studios/minecraft-eggs)
#  as root, with the server files mounted at /mnt/server.
#
#  Supported server types (SERVER_TYPE):
#    vanilla | paper | spigot | purpur | folia | forge | neoforge | fabric |
#    quilt | mohist | magma | bungeecord | velocity | waterfall | bedrock |
#    nukkit | pocketmine | github | custom
#
#  'github' installs from a GitHub repository (GITHUB_REPO=owner/name, a full
#  GitHub URL also works; optional GITHUB_TAG and GITHUB_ASSET filter).
#  GITHUB_TOKEN (optional) enables private repositories and avoids API rate
#  limits. Release assets (.jar/.zip) are preferred; repos without releases
#  are fetched as a source archive of the newest commit. The installed
#  release/commit is recorded in .mc-instance.conf, so a later Reinstall
#  detects new commits/releases, archives the current codebase into archive/
#  and fetches the updated one (nothing is wiped; failed downloads never
#  destroy the previously working jar).
#
#  Every project supports its full version history; unknown versions fall
#  back to the latest release with a warning. Setting DL_URL bypasses the
#  project logic entirely (downloads straight into the server jar file).
#
#  Behavior switches (egg variables):
#    AUTO_UPDATE=1 (default)  always (re)install on reinstall
#    AUTO_UPDATE=0            skip installation if the server files exist
#    KEEP_BACKUP=1            keep the previous jar as <name>.old
#    SHOW_VERSIONS=1          print all available versions and exit (no install)
#    DEBUG=1                  run with bash -x (verbose troubleshooting output)
#    MOTD / MAX_PLAYERS / ONLINE_MODE / VIEW_DISTANCE / DIFFICULTY / GAMEMODE /
#    PVP / RCON_PASSWORD      applied to a freshly generated server.properties
#    EXTRA_URLS               extra files to download (dest/name|url per line)
#    WORLD_URL                world zip to import into ./world (Java servers)
# =============================================================================

if [ -d /mnt/server ]; then
    cd /mnt/server 2>/dev/null || true
elif [ -d /home/container ]; then
    cd /home/container 2>/dev/null || true
else
    cd "$(pwd)" 2>/dev/null || true
fi
SERVER_DIR="$(pwd)"

# Ensure core utilities are available in minimal/custom installer images
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y -qq curl jq unzip tar ca-certificates >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl jq unzip tar ca-certificates >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q curl jq unzip tar ca-certificates >/dev/null 2>&1 || true
    fi
fi

DEBUG="${DEBUG:-0}"
[ "${DEBUG}" = "1" ] && set -x

log()  { echo -e "\033[1m\033[33m[install]\033[0m $*"; }
ok()   { echo -e "\033[1m\033[32m[install][OK]\033[0m $*"; }
warn() { echo -e "\033[1m\033[33m[install][warn]\033[0m $*"; }

fail() {
    local err_msg="$1"
    local suggestion="${2:-}"
    local divider
    divider=$(printf '%*s' 62 '' | tr ' ' '=')
    local sub_divider
    sub_divider=$(printf '%*s' 62 '' | tr ' ' '-')

    echo ""
    echo -e "\033[1;31m${divider}\033[0m"
    echo -e "\033[1;31m  [INSTALL ERROR] Server installation could not complete\033[0m"
    echo -e "\033[1;31m${divider}\033[0m"
    echo -e "  \033[1;33mError Details:\033[0m ${err_msg}"
    echo -e "  \033[1;36mServer Type  :\033[0m ${PROJECT_TYPE:-vanilla} (${MC_VERSION:-latest})"
    [ -n "${BUILD_NUMBER:-}" ] && [ "${BUILD_NUMBER}" != "latest" ] && echo -e "  \033[1;36mBuild Number :\033[0m ${BUILD_NUMBER}"
    [ -n "${LOADER_VERSION:-}" ] && [ "${LOADER_VERSION}" != "latest" ] && echo -e "  \033[1;36mLoader Ver   :\033[0m ${LOADER_VERSION}"
    [ -n "${DL_URL:-}" ] && echo -e "  \033[1;36mDownload URL :\033[0m ${DL_URL}"
    echo -e "  \033[1;36mTarget Path  :\033[0m ${SERVER_DIR:-$(pwd)}/${JARFILE:-server.jar}"
    echo -e "  \033[1;36mFree Space   :\033[0m $(df -h . 2>/dev/null | awk 'NR==2 {print $4}' || echo 'unknown')"

    echo -e "\033[2;37m${sub_divider}\033[0m"
    echo -e "  \033[1;32mTroubleshooting Guide:\033[0m"
    if [ -n "${suggestion}" ]; then
        echo -e "  • ${suggestion}"
    else
        case "${PROJECT_TYPE}" in
            vanilla | paper | purpur | folia | fabric | quilt | spigot)
                echo -e "  • Ensure Minecraft Version '${MC_VERSION}' exists for ${PROJECT_TYPE}."
                echo -e "  • Check your panel network / DNS connectivity to download repositories."
                echo -e "  • Set SHOW_VERSIONS=1 in panel Variables and Reinstall to see available versions."
                ;;
            forge | neoforge)
                echo -e "  • Ensure loader version '${LOADER_VERSION}' is compatible with MC '${MC_VERSION}'."
                echo -e "  • Allocate sufficient memory (at least 2048 MB is recommended for Forge installer)."
                ;;
            github)
                echo -e "  • Verify that '${GITHUB_REPO}' exists and has releases (or source code)."
                echo -e "  • Set GITHUB_TOKEN for private repositories, or when the API rate-limits you (403)."
                echo -e "  • Check if GITHUB_ASSET matches the release asset filename."
                ;;
            custom)
                echo -e "  • Check that DL_URL points to a valid, publicly reachable direct download link."
                ;;
            *)
                echo -e "  • Verify server configuration variables and retry the installation."
                ;;
        esac
    fi
    echo -e "  • For full verbose installer trace, set DEBUG=1 in panel Variables."
    echo -e "\033[1;31m${divider}\033[0m"
    echo ""
    sleep 3
    exit 1
}

# ---------------------------------------------------------------------------
# Persistent error logging & traced execution (kept inside the server dir)
# ---------------------------------------------------------------------------
ERROR_LOG="${SERVER_DIR}/install-error.log"

log_rotate_file() { # keep the log bounded (~512 KB)
    local max=524288
    [ -f "$1" ] || return 0
    [ "$(wc -c < "$1" 2>/dev/null || echo 0)" -le "$max" ] || mv -f "$1" "$1.old" 2>/dev/null || true
}

log_event() {
    printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "${ERROR_LOG}" 2>/dev/null || true
}

PROJECT_TYPE=$(echo "${SERVER_TYPE:-vanilla}" | tr '[:upper:]' '[:lower:]')
MC_VERSION="${MINECRAFT_VERSION:-latest}"
BUILD_NUMBER="${BUILD_NUMBER:-latest}"
LOADER_VERSION="${LOADER_VERSION:-latest}"
JARFILE="${SERVER_JARFILE:-server.jar}"
MOTD="${MOTD:-A Minecraft Server}"
MAX_PLAYERS="${MAX_PLAYERS:-20}"
ONLINE_MODE="${ONLINE_MODE:-true}"
VIEW_DISTANCE="${VIEW_DISTANCE:-10}"
DIFFICULTY="${DIFFICULTY:-}"
GAMEMODE="${GAMEMODE:-}"
PVP="${PVP:-true}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
AUTO_UPDATE="${AUTO_UPDATE:-1}"
KEEP_BACKUP="${KEEP_BACKUP:-0}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TAG="${GITHUB_TAG:-latest}"
GITHUB_ASSET="${GITHUB_ASSET:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
SHOW_VERSIONS="${SHOW_VERSIONS:-0}"
EXTRA_URLS="${EXTRA_URLS:-}"
WORLD_URL="${WORLD_URL:-}"
RESOLVED_VERSION=""

USER_AGENT="MultiMinecraftEgg/1.0 (PotenFYR Studios; https://github.com/PotenFYR-Studios/Minecraft-Eggs)"

# GitHub API/download helper. GITHUB_TOKEN (optional) authenticates private
# repositories and lifts the 60 req/hour anonymous rate limit - without it,
# busy nodes get 403s that look like "github fetch doesn't work".
gh_auth_header() {
    [ -n "${GITHUB_TOKEN}" ] && printf 'Authorization: Bearer %s' "${GITHUB_TOKEN}"
}

gh_download() { # $1 = url, $2 = destination file (omit to print to stdout)
    local auth
    auth=$(gh_auth_header)
    if [ "$#" -ge 2 ]; then
        if [ -n "${auth}" ]; then
            curl -fsSL --retry 3 --connect-timeout 20 -A "${USER_AGENT}" -H "${auth}" -o "$2" "$1"
        else
            curl -fsSL --retry 3 --connect-timeout 20 -A "${USER_AGENT}" -o "$2" "$1"
        fi
    else
        if [ -n "${auth}" ]; then
            curl -fsSL --retry 3 --connect-timeout 20 -A "${USER_AGENT}" -H "${auth}" "$1"
        else
            curl -fsSL --retry 3 --connect-timeout 20 -A "${USER_AGENT}" "$1"
        fi
    fi
}

gh_api() { # $1 = API path (after https://api.github.com) -> JSON on stdout
    gh_download "https://api.github.com${1}"
}

# Accepts owner/repo, https://github.com/owner/repo, git@github.com:owner/repo
# and optional .git / trailing-slash suffixes; prints a clean owner/repo.
normalize_github_repo() {
    local r="${1:-}"
    r="$(printf '%s' "${r}" | tr -d '[:space:]')"
    r="${r##*github.com[:/]}"   # strip any URL / scp-style prefix
    r="${r%/}"                  # trailing slash
    r="${r%.git}"               # .git suffix
    r="${r%/}"
    printf '%s' "${r}"
}

# Backup (or remove) an existing server jar before replacing it.
backup_existing_jar() {
    [ -f "${JARFILE}" ] || return 0
    if [ "${KEEP_BACKUP}" = "1" ]; then
        mv -f "${JARFILE}" "${JARFILE}.old"
        log "Previous jar kept as ${JARFILE}.old"
    else
        rm -f "${JARFILE}"
        log "Removed previous jar (KEEP_BACKUP=0)"
    fi
}

download() { # $1 = url, $2 = destination (atomic + cleaned up on failure)
    # The replacement is downloaded to a temp file FIRST; the previous jar is
    # only removed after the new one is fully on disk. Deleting the jar up
    # front turned every failed download (bad URL, GitHub rate limit, offline
    # node) into a "reinstall wiped my server" report.
    local dest="$2" tmp="${2}.download.$$"
    if ! curl -fsSL --retry 3 --connect-timeout 20 -A "${USER_AGENT}" -o "${tmp}" "$1"; then
        rm -f "${tmp}"
        fail "Failed to download $1"
    fi
    if [ "${dest}" = "${JARFILE}" ]; then
        backup_existing_jar
    fi
    mv -f "${tmp}" "${dest}"
}

# ---------------------------------------------------------------------------
# Instance management: switch type/version without ever losing data
# ---------------------------------------------------------------------------
INSTANCE_FILE="${SERVER_DIR}/.mc-instance.conf"

instance_get() { # key -> value (plain KEY=VALUE store, zero dependencies)
    [ -f "${INSTANCE_FILE}" ] || return 1
    local val
    val=$(grep -E "^$1=" "${INSTANCE_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2-)
    [ -n "${val}" ] || return 1
    printf '%s' "${val}"
}

instance_set_kv() { # key value : upsert without external tools
    local k="$1" v="$2" tmp="${INSTANCE_FILE}.tmp"
    if [ -f "${INSTANCE_FILE}" ]; then
        awk -v k="${k}" -v v="${v}" \
            'BEGIN { FS = "="; OFS = "=" }
             $1 == k { found = 1; print k, v; next }
             { print }
             END { if (!found) print k, v }' "${INSTANCE_FILE}" > "${tmp}" \
            && mv -f "${tmp}" "${INSTANCE_FILE}"
    else
        printf '%s=%s\n' "${k}" "${v}" > "${tmp}" && mv -f "${tmp}" "${INSTANCE_FILE}"
    fi
}

major_line() { # "1.21.4" -> "1.21", "26.1.2" -> "26.1"; empty for keywords
    echo "${1:-}" | grep -oE '^[0-9]+\.[0-9]+' || true
}

archive_previous_instance() {
    local stamp dest count base f safe_type safe_mc
    safe_type=$(echo "${PREV_TYPE:-unknown}" | tr -c 'A-Za-z0-9._-' '_' | sed 's/_$//')
    safe_mc=$(echo "${PREV_MC:-unknown}" | tr -c 'A-Za-z0-9._-' '_' | sed 's/_$//')
    stamp=$(date +%Y%m%d-%H%M%S)
    dest="${SERVER_DIR}/archive/${safe_type}-${safe_mc}-${stamp}"
    if ! mkdir -p "${dest}" 2>/dev/null; then
        warn "Could not create archive folder '${dest}'; keeping previous files in place"
        return 0
    fi
    count=0
    shopt -s dotglob nullglob
    for f in "${SERVER_DIR}"/*; do
        base=$(basename "${f}")
        case "${base}" in
            archive|.mc-instance.conf|.multi-mc.conf|.gitkeep|.potenfyr|.logs|install-error.log|install-error.log.old) continue ;;
        esac
        if mv -f -- "${f}" "${dest}/" 2>/dev/null; then
            count=$((count + 1))
        fi
    done
    shopt -u dotglob nullglob
    warn "Breaking change detected: ${ARCHIVE_REASON}"
    warn "Your previous server data was NOT deleted."
    ok   "Archived ${count} item(s) to: archive/${safe_type}-${safe_mc}-${stamp}"
    log  "The new ${PROJECT_TYPE} ${MC_VERSION} server was installed fresh beside it."
    log  "Review the archive/ folder in the panel File Manager (or SFTP) and delete"
    log  "it manually once you no longer need the old files."
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

mc_latest_release() {
    curl -fsSL -A "${USER_AGENT}" https://piston-meta.mojang.com/mc/game/version_manifest_v2.json | jq -r '.latest.release'
}

mc_latest_snapshot() {
    curl -fsSL -A "${USER_AGENT}" https://piston-meta.mojang.com/mc/game/version_manifest_v2.json | jq -r '.latest.snapshot'
}

# Java generation required for a given Minecraft version (supports snapshots, alpha/beta, future)
java_for_mc() {
    # If user explicitly set JAVA_VERSION, that takes absolute precedence
    if [ -n "${JAVA_VERSION:-}" ]; then
        echo "${JAVA_VERSION}"
        return
    fi
    case "$1" in
        latest | latest-snapshot)
            echo "26"
            ;;
        [3-9][0-9].* | 2[7-9].*)
            # Future Minecraft versions (e.g. 27.x, 28.x)
            echo "$1" | cut -d. -f1
            ;;
        26.*)
            echo "26"
            ;;
        2[0-5].*)
            echo "25"
            ;;
        2[6-9]w* | [3-9][0-9]w*)
            # Snapshots (e.g. 26w07a, 27w01a)
            echo "26"
            ;;
        25w*)
            echo "25"
            ;;
        24w*)
            echo "21"
            ;;
        20w4[5-9]* | 20w5* | 2[1-3]w*)
            echo "17"
            ;;
        1.20.[5-9]* | 1.2[1-9]*)
            echo "21"
            ;;
        1.17* | 1.18* | 1.19* | 1.20 | 1.20.[1-4]*)
            echo "17"
            ;;
        a1.* | b1.* | c0.* | in-* | rd-* | inf-* | 1.1[0-6]* | 1.[0-9]*)
            echo "8"
            ;;
        *)
            echo "21"
            ;;
    esac
}

java_bin_for_mc() {
    # 1. Custom Java URL
    if [ -n "${JAVA_URL:-}" ]; then
        if command -v install-java.sh >/dev/null 2>&1; then
            install-java.sh "${JAVA_URL}" "custom" >&2 2>/dev/null || true
        fi
        for cand in "/opt/java/custom" "${SERVER_DIR}/java" "${SERVER_DIR}/jre" "${SERVER_DIR}/jdk" "/mnt/server/java" "/mnt/server/jre" "/mnt/server/jdk" "/home/container/java" "/home/container/jre" "/home/container/jdk" "${HOME}/.java/custom"; do
            if [ -x "${cand}/bin/java" ]; then
                echo "${cand}/bin/java"
                return
            fi
        done
    fi

    # 2. Local custom Java in server directory (or mounted directory)
    for cand in "${SERVER_DIR}/java" "${SERVER_DIR}/jre" "${SERVER_DIR}/jdk" "/mnt/server/java" "/mnt/server/jre" "/mnt/server/jdk" "/home/container/java" "/home/container/jre" "/home/container/jdk"; do
        if [ -x "${cand}/bin/java" ]; then
            echo "${cand}/bin/java"
            return
        fi
    done

    local jv
    jv=$(java_for_mc "$1")
    if [[ "${jv}" =~ ^https?:// ]]; then
        if command -v install-java.sh >/dev/null 2>&1; then
            install-java.sh "${jv}" "custom" >&2 2>/dev/null || true
        fi
        if [ -x "/opt/java/custom/bin/java" ]; then
            echo "/opt/java/custom/bin/java"
            return
        fi
    fi

    for cand in "/opt/java/${jv}" "${HOME}/.java/${jv}"; do
        if [ -x "${cand}/bin/java" ]; then
            echo "${cand}/bin/java"
            return
        fi
    done

    # If missing, attempt on-demand installation via install-java.sh if present
    if command -v install-java.sh >/dev/null 2>&1; then
        install-java.sh "${jv}" >&2 2>/dev/null || true
        for cand in "/opt/java/${jv}" "${HOME}/.java/${jv}"; do
            if [ -x "${cand}/bin/java" ]; then
                echo "${cand}/bin/java"
                return
            fi
        done
    fi

    # Fall back to newest runtime installed in /opt/java
    local dir cand
    for dir in "/opt/java" "${HOME}/.java"; do
        if [ -d "${dir}" ]; then
            for cand in $(find "${dir}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V -r); do
                if [ -x "${dir}/${cand}/bin/java" ]; then
                    echo "${dir}/${cand}/bin/java"
                    return
                fi
            done
        fi
    done

    echo "java"
}

ensure_server_properties() {
    [ -f server.properties ] && return 0
    # Do not write server.properties by default; let the server software generate native configs
    # unless explicitly requested or custom properties were defined
    if [ "${GENERATE_CONFIG:-0}" != "1" ] && [ "${MOTD:-A Minecraft Server}" = "A Minecraft Server" ] && [ "${MAX_PLAYERS:-20}" = "20" ] && [ "${ONLINE_MODE:-true}" = "true" ] && [ -z "${DIFFICULTY:-}" ] && [ -z "${GAMEMODE:-}" ] && [ -z "${RCON_PASSWORD:-}" ]; then
        return 0
    fi
    {
        printf 'server-ip=0.0.0.0\n'
        printf 'server-port=25565\n'
        printf 'query.port=25565\n'
        printf 'motd=%s\n' "${MOTD:-A Minecraft Server}"
        printf 'max-players=%s\n' "${MAX_PLAYERS:-20}"
        printf 'view-distance=%s\n' "${VIEW_DISTANCE:-10}"
        printf 'online-mode=%s\n' "${ONLINE_MODE:-true}"
        [ -n "${DIFFICULTY:-}" ] && printf 'difficulty=%s\n' "${DIFFICULTY}"
        [ -n "${GAMEMODE:-}" ] && printf 'gamemode=%s\n' "${GAMEMODE}"
        [ -n "${PVP:-}" ] && printf 'pvp=%s\n' "${PVP}"
        if [ -n "${RCON_PASSWORD:-}" ]; then
            printf 'enable-rcon=true\n'
            printf 'rcon.password=%s\n' "${RCON_PASSWORD}"
        else
            printf 'enable-rcon=false\n'
        fi
    } > server.properties
    log "Wrote custom server.properties (motd='${MOTD:-A Minecraft Server}', max-players=${MAX_PLAYERS:-20})"
}

# ---------------------------------------------------------------------------
# Extra downloads (EXTRA_URLS / WORLD_URL)
# ---------------------------------------------------------------------------

# EXTRA_URLS: one entry per line. Each entry is either a plain URL (file lands
# in the server root) or "dest/name|url" (file lands in dest/, e.g. plugins/).
install_extra_urls() {
    [ -n "${EXTRA_URLS}" ] || return 0
    log "Downloading extra files from EXTRA_URLS..."
    local IFS=$'\n' entry dest url name
    for entry in ${EXTRA_URLS}; do
        [ -z "${entry}" ] && continue
        dest=""
        url="${entry}"
        case "${entry}" in
            *\|*)
                dest="${entry%%|*}"
                url="${entry#*|}"
                ;;
        esac
        # dest is a directory: strip slashes and validate (no path traversal)
        dest=$(echo "${dest}" | sed 's:/*$::')
        if [ -n "${dest}" ] && { ! echo "${dest}" | grep -qE '^[A-Za-z0-9_./-]+$' || echo "${dest}" | grep -q '\.\.'; }; then
            warn "Skipping EXTRA_URLS entry with unsafe destination '${dest}'"
            continue
        fi
        name="${url##*/}"
        name=$(echo "${name}" | sed 's/[?].*//')
        # Sanitize: only safe file names reach the filesystem.
        if ! echo "${name}" | grep -qE '^[A-Za-z0-9._-]+$'; then
            warn "Unsafe file name '${name}' - saving as extra-file"
            name="extra-file"
        fi
        [ -n "${dest}" ] && mkdir -p "${dest}"
        if curl -fsSL --retry 2 --connect-timeout 20 -A "${USER_AGENT}" -o "${dest:+${dest}/}${name}" "${url}"; then
            case "${name}" in
                *.zip)
                    unzip -o "${dest:+${dest}/}${name}" -d "${dest}" > /dev/null 2>&1
                    rm -f "${dest:+${dest}/}${name}"
                    log "Extracted ${dest:+${dest}/}${name}"
                    ;;
                *)
                    log "Saved ${dest:+${dest}/}${name}"
                    ;;
            esac
        else
            warn "Failed to download extra URL: ${url}"
        fi
    done
}

# WORLD_URL: a world zip (e.g. from Planet Minecraft or a previous host) is
# downloaded and unpacked into ./world. A single top-level folder inside the
# archive is unwrapped automatically.
install_world() {
    [ -n "${WORLD_URL}" ] || return 0
    log "Downloading world from ${WORLD_URL}"
    if ! curl -fsSL --retry 3 --connect-timeout 20 -A "${USER_AGENT}" -o /tmp/world.zip "${WORLD_URL}"; then
        warn "Failed to download world archive"
        return 0
    fi
    mkdir -p world
    if unzip -o /tmp/world.zip -d world > /dev/null 2>&1; then
        local sub topfiles
        sub=$(find world -mindepth 1 -maxdepth 1 -type d | head -n1)
        topfiles=$(find world -mindepth 1 -maxdepth 1 -type f | wc -l)
        if [ -n "${sub}" ] && [ "${topfiles}" -eq 0 ]; then
            mv "${sub}"/* world/ 2>/dev/null || true
            mv "${sub}"/.[!.]* world/ 2>/dev/null || true
            rmdir "${sub}" 2>/dev/null || true
            log "Unwrapped single-folder world archive"
        fi
        log "World imported into ./world"
    else
        warn "World archive could not be extracted (is it a valid zip?)"
    fi
    rm -f /tmp/world.zip
}

ensure_config_yml() {
    [ -f config.yml ] && return 0
    [ "${GENERATE_CONFIG:-0}" = "1" ] || return 0
    cat > config.yml <<'EOF'
listeners:
- query_port: 25577
  motd: '&1A BungeeCord Server'
  query_enabled: false
  ping_passthrough: false
  priorities:
  - lobby
  bind_local_address: true
  host: 0.0.0.0:25577
  max_players: 100
  tab_size: 60
  force_default_server: false
  tab_list: GLOBAL_PING
  default_server: lobby
  forced_hosts: {}
groups: {}
remote_ping_cache: -1
player_limit: -1
ip_forward: false
timeout: 30000
log_commands: false
online_mode: true
servers:
  lobby:
    address: 127.0.0.1:25565
    restricted: false
disabled_commands: []
EOF
    log "Wrote default config.yml"
}

ensure_velocity_toml() {
    [ -f velocity.toml ] && return 0
    [ "${GENERATE_CONFIG:-0}" = "1" ] || return 0
    cat > velocity.toml <<'EOF'
bind = "0.0.0.0:25577"
motd = "&1A Velocity Server"
show-max-players = 500
online-mode = true
player-info-forwarding-mode = "none"
forwarding-secret-file = "forwarding.secret"

[servers]
lobby = "127.0.0.1:25565"

[forced-hosts]
"lobby.example.com" = "lobby"

[advanced]
compression-threshold = 256
login-ratelimit = 3000
connection-timeout = 5000
read-timeout = 30000
haproxy-protocol = false
tcp-fast-open = false
bungee-plugin-message-channel = true
show-ping-requests = false
failover-on-unexpected-server-disconnect = true
announce-proxy-commands = true

[query]
enabled = false
port = 25577

[permissions]
default-enabled = []
EOF
    log "Wrote default velocity.toml"
}

# ---------------------------------------------------------------------------
# Installers
# ---------------------------------------------------------------------------

install_vanilla() {
    local manifest ver entry_url vjson url
    log "Installing vanilla Minecraft (${MC_VERSION})"
    manifest=$(curl -fsSL -A "${USER_AGENT}" https://piston-meta.mojang.com/mc/game/version_manifest_v2.json) \
        || fail "Cannot reach the Mojang version manifest"
    case "${MC_VERSION}" in
        latest) ver=$(echo "${manifest}" | jq -r '.latest.release') ;;
        latest-snapshot) ver=$(echo "${manifest}" | jq -r '.latest.snapshot') ;;
        *)
            ver=$(echo "${manifest}" | jq -r --arg v "${MC_VERSION}" '.versions[] | select(.id == $v) | .id' | head -n1)
            [ -z "${ver}" ] && fail "Minecraft version '${MC_VERSION}' does not exist"
            ;;
    esac
    entry_url=$(echo "${manifest}" | jq -r --arg v "${ver}" '.versions[] | select(.id == $v) | .url // empty' | head -n1)
    [ -z "${entry_url}" ] && fail "Mojang has no version entry for ${ver}"
    vjson=$(curl -fsSL -A "${USER_AGENT}" "${entry_url}") || fail "Cannot fetch version data for ${ver}"
    url=$(echo "${vjson}" | jq -r '.downloads.server.url // empty' | head -n1)
    [ -z "${url}" ] && fail "Mojang does not distribute a server jar for ${ver}"
    RESOLVED_VERSION="${ver}"
    log "Downloading vanilla ${ver} server jar"
    download "${url}" "${JARFILE}"
}

install_papermc() { # $1 = project (paper|folia|velocity|waterfall)
    local project="$1" data ver builds build url
    log "Installing ${project} (${MC_VERSION}${BUILD_NUMBER:+ build ${BUILD_NUMBER}})"
    data=$(curl -fsSL -A "${USER_AGENT}" "https://fill.papermc.io/v3/projects/${project}") \
        || fail "Cannot reach the PaperMC download API"
    if [ "${MC_VERSION}" = "latest" ]; then
        ver=$(echo "${data}" | jq -r '([.versions[][]][0] // [.versions | keys[]][0])')
    elif curl -fsSL -A "${USER_AGENT}" "https://fill.papermc.io/v3/projects/${project}/versions/${MC_VERSION}" -o /dev/null 2>/dev/null; then
        ver="${MC_VERSION}"
    elif echo "${data}" | jq -e --arg g "${MC_VERSION}" '.versions[$g]' >/dev/null 2>&1; then
        ver=$(echo "${data}" | jq -r --arg g "${MC_VERSION}" '.versions[$g][0]')
    else
        warn "Version '${MC_VERSION}' not found for ${project}, defaulting to latest"
        ver=$(echo "${data}" | jq -r '([.versions[][]][0] // [.versions | keys[]][0])')
    fi
    builds=$(curl -fsSL -A "${USER_AGENT}" "https://fill.papermc.io/v3/projects/${project}/versions/${ver}" | jq -r '.builds')
    if [ "${BUILD_NUMBER}" = "latest" ]; then
        build=$(echo "${builds}" | jq -r '.[0]')
    elif echo "${builds}" | jq -e --arg b "${BUILD_NUMBER}" 'index($b|tonumber? // $b)' > /dev/null 2>&1; then
        build="${BUILD_NUMBER}"
    else
        warn "Build ${BUILD_NUMBER} not found for ${project} ${ver}, using latest"
        build=$(echo "${builds}" | jq -r '.[0]')
    fi
    url=$(curl -fsSL -A "${USER_AGENT}" "https://fill.papermc.io/v3/projects/${project}/versions/${ver}/builds/${build}" | jq -r '(.downloads["server:default"].url // (.downloads | to_entries[0].value.url))')
    [ -z "${url}" ] || [ "${url}" = "null" ] && fail "No download found for ${project} ${ver} build ${build}"
    RESOLVED_VERSION="${ver} (build ${build})"
    log "Downloading ${project} ${ver} build ${build}"
    download "${url}" "${JARFILE}"
}

install_purpur() {
    local data ver url
    log "Installing Purpur (${MC_VERSION}${BUILD_NUMBER:+ build ${BUILD_NUMBER}})"
    data=$(curl -fsSL -A "${USER_AGENT}" https://api.purpurmc.org/v2/purpur) \
        || fail "Cannot reach the Purpur download API"
    if [ "${MC_VERSION}" = "latest" ]; then
        ver=$(echo "${data}" | jq -r '.versions[-1]')
    else
        ver=$(echo "${data}" | jq -r --arg v "${MC_VERSION}" '.versions | index($v) as $i | if $i == null then empty else .[$i] end' | head -n1)
        [ -z "${ver}" ] && { warn "Version '${MC_VERSION}' not found for Purpur, defaulting to latest"; ver=$(echo "${data}" | jq -r '.versions[-1]'); }
    fi
    if [ "${BUILD_NUMBER}" = "latest" ]; then
        url="https://api.purpurmc.org/v2/purpur/${ver}/latest/download"
    else
        url="https://api.purpurmc.org/v2/purpur/${ver}/${BUILD_NUMBER}/download"
    fi
    RESOLVED_VERSION="${ver}"
    log "Downloading Purpur ${ver}"
    download "${url}" "${JARFILE}"
}

install_spigot() {
    local ver="${MC_VERSION}" jv jdk_arch mem built
    log "Building Spigot ${ver} with BuildTools (this can take several minutes)"
    RESOLVED_VERSION="${ver}"
    apt-get update -qq > /dev/null 2>&1 || true
    apt-get install -y -qq git > /dev/null 2>&1 || fail "Failed to install git (required by BuildTools)"
    jv=$(java_for_mc "${ver}")
    case "$(uname -m)" in
        x86_64) jdk_arch="x64" ;;
        aarch64) jdk_arch="aarch64" ;;
        *) fail "Unsupported architecture for BuildTools" ;;
    esac
    log "Downloading temporary JDK ${jv} for the build..."
    curl -fsSL -A "${USER_AGENT}" "https://api.adoptium.net/v3/binary/latest/${jv}/ga/linux/${jdk_arch}/jdk/hotspot/normal/eclipse" -o /tmp/jdk.tar.gz \
        || fail "Failed to download JDK ${jv}"
    mkdir -p /tmp/jdk && tar -xzf /tmp/jdk.tar.gz -C /tmp/jdk --strip-components=1 && rm -f /tmp/jdk.tar.gz
    mkdir -p /tmp/buildtools && cd /tmp/buildtools || exit 1
    download "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" BuildTools.jar
    mem=${SERVER_MEMORY:-1024}
    [ "${mem}" -lt 1024 ] 2>/dev/null && mem=1024
    if [ "${ver}" = "latest" ]; then
        /tmp/jdk/bin/java -Xms512M -Xmx${mem}M -jar BuildTools.jar || fail "BuildTools failed (is ${ver} a valid version / is the memory allocation sufficient?)"
    else
        /tmp/jdk/bin/java -Xms512M -Xmx${mem}M -jar BuildTools.jar --rev "${ver}" || fail "BuildTools failed (is ${ver} a valid version / is the memory allocation sufficient?)"
    fi
    built=$(ls spigot-*.jar 2>/dev/null | grep -v BuildTools | head -n1)
    [ -z "${built}" ] && fail "BuildTools finished but no Spigot jar was produced"
    mv "${built}" "${SERVER_DIR}/${JARFILE}"
    cd "${SERVER_DIR}" || exit 1
    rm -rf /tmp/buildtools /tmp/jdk
    ok "Spigot build complete"
}

install_forge() {
    local mc="${MC_VERSION}" fv loader
    log "Installing Forge (${MC_VERSION}${LOADER_VERSION:+ loader ${LOADER_VERSION}})"
    loader="${LOADER_VERSION}"
    fv=$(resolve_forge_version "${mc}" "${loader}")
    [ -z "${fv}" ] && fail "Could not resolve a Forge version for Minecraft ${mc}"
    RESOLVED_VERSION="${fv}"
    log "Using Forge ${fv}"
    download "https://maven.minecraftforge.net/net/minecraftforge/forge/${fv}/forge-${fv}-installer.jar" forge-installer.jar
    "$(java_bin_for_mc "${mc}")" -jar forge-installer.jar --installServer || fail "Forge installer failed"
    rm -f forge-installer.jar
    if [ -f unix_args.txt ] || ls libraries/net/minecraftforge/forge/*/unix_args.txt > /dev/null 2>&1; then
        ln -sf libraries/net/minecraftforge/forge/*/unix_args.txt unix_args.txt 2>/dev/null || true
    else
        built=$(ls forge-*.jar 2>/dev/null | grep -v installer | head -n1)
        [ -z "${built}" ] && built=$(ls libraries/net/minecraftforge/forge/*/forge-*.jar 2>/dev/null | grep -v installer | head -n1)
        [ -z "${built}" ] && fail "Forge installed but no launcher jar was produced"
        mv "${built}" "${JARFILE}"
    fi
    ensure_server_properties
    ok "Forge install complete"
}

# Resolves a full Forge maven version (e.g. "1.20.1-47.4.23" or
# "1.8.9-11.15.1.2318-1.8.9") using promotions data and maven metadata.
resolve_forge_version() {
    local mc="$1" loader="$2" promos v latest_mc cand
    promos=$(curl -fsSL -A "${USER_AGENT}" https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json) \
        || return 1
    if [ "${mc}" = "latest" ]; then
        latest_mc=$(echo "${promos}" | jq -r '.promos | keys[] | select(endswith("-latest")) | rtrimstr("-latest")' | sort -V | tail -n1)
        [ -z "${latest_mc}" ] && return 1
        mc="${latest_mc}"
        v=$(echo "${promos}" | jq -r --arg k "${mc}" '.promos["\($k)-latest"] // empty')
    elif [ "${loader}" != "latest" ] && [ -n "${loader}" ]; then
        v="${loader}"
    else
        v=$(echo "${promos}" | jq -r --arg k "${mc}" '.promos["\($k)-latest"] // .promos["\($k)-recommended"] // empty')
    fi
    if [ -n "${v}" ] && [ -n "${mc}" ]; then
        # Modern naming: "1.20.1-47.4.23"; legacy (1.7.x/1.8.x): "1.8.9-11.15.1.2318-1.8.9"
        cand="${mc}-${v}"
        case "${mc}" in
            1.7* | 1.8*) cand="${cand}-${mc}" ;;
        esac
        if curl -fsSL -A "${USER_AGENT}" -o /dev/null "https://maven.minecraftforge.net/net/minecraftforge/forge/${cand}/forge-${cand}-installer.jar"; then
            echo "${cand}"
            return 0
        fi
    fi
    # Fall back to maven metadata (covers versions missing from promotions)
    curl -fsSL -A "${USER_AGENT}" https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml \
        | grep -oP '(?<=<version>)[^<]+' | grep "^${mc}-" | sort -V | tail -n1
}

install_neoforge() {
    local mc="${MC_VERSION}" group base fv prefix
    log "Installing NeoForge (${MC_VERSION}${LOADER_VERSION:+ loader ${LOADER_VERSION}})"
    if [ "${mc}" = "1.20.1" ]; then
        group="forge"
        base="https://maven.neoforged.net/releases/net/neoforged/forge"
        prefix="1.20.1-"
    else
        group="neoforge"
        base="https://maven.neoforged.net/releases/net/neoforged/neoforge"
        prefix=$(echo "${mc}" | sed -E 's/^1\.//')
    fi
    if [ "${mc}" = "latest" ]; then
        fv=$(curl -fsSL -A "${USER_AGENT}" "${base}/maven-metadata.xml" | grep -oP '(?<=<latest>)[^<]+' | head -n1)
    elif [ "${LOADER_VERSION}" != "latest" ]; then
        fv="${LOADER_VERSION}"
    else
        fv=$(curl -fsSL -A "${USER_AGENT}" "${base}/maven-metadata.xml" | grep -oP '(?<=<version>)[^<]+' | grep "^${prefix}[.-]" | sort -V | tail -n1)
    fi
    [ -z "${fv}" ] && fail "Could not resolve a NeoForge version for Minecraft ${mc}"
    RESOLVED_VERSION="${fv}"
    log "Using NeoForge ${fv}"
    download "https://maven.neoforged.net/releases/net/neoforged/${group}/${fv}/${group}-${fv}-installer.jar" neoforge-installer.jar
    "$(java_bin_for_mc "${mc}")" -jar neoforge-installer.jar --installServer || fail "NeoForge installer failed"
    rm -f neoforge-installer.jar
    ln -sf libraries/net/neoforged/${group}/*/unix_args.txt unix_args.txt 2>/dev/null || true
    ensure_server_properties
    ok "NeoForge install complete"
}

install_fabric() {
    local mc="${MC_VERSION}" installer_url loader_args=""
    log "Installing Fabric (${MC_VERSION}${LOADER_VERSION:+ loader ${LOADER_VERSION}})"
    installer_url=$(curl -fsSL -A "${USER_AGENT}" https://meta.fabricmc.net/v2/versions/installer | jq -r '.[0].url')
    [ -z "${installer_url}" ] && fail "Cannot resolve the Fabric installer"
    [ "${mc}" = "latest" ] && mc=$(mc_latest_release)
    if [ "${LOADER_VERSION}" != "latest" ]; then loader_args="-loader ${LOADER_VERSION}"; fi
    download "${installer_url}" fabric-installer.jar
    "$(java_bin_for_mc "${mc}")" -jar fabric-installer.jar server -mcversion "${mc}" ${loader_args} -downloadMinecraft \
        || fail "Fabric installer failed"
    rm -f fabric-installer.jar
    mv -f fabric-server-launch.jar "${JARFILE}"
    RESOLVED_VERSION="${mc}"
    ensure_server_properties
    ok "Fabric install complete"
}

install_quilt() {
    local mc="${MC_VERSION}" installer_url loader=""
    log "Installing Quilt (${MC_VERSION}${LOADER_VERSION:+ loader ${LOADER_VERSION}})"
    installer_url=$(curl -fsSL -A "${USER_AGENT}" https://meta.quiltmc.org/v3/versions/installer | jq -r '.[0].url')
    [ -z "${installer_url}" ] && fail "Cannot resolve the Quilt installer"
    [ "${mc}" = "latest" ] && mc=$(mc_latest_release)
    if [ "${LOADER_VERSION}" != "latest" ]; then
        loader="${LOADER_VERSION}"
    else
        loader=$(curl -fsSL -A "${USER_AGENT}" "https://meta.quiltmc.org/v3/versions/loader/${mc}" | jq -r '.[0].loader.version')
    fi
    download "${installer_url}" quilt-installer.jar
    "$(java_bin_for_mc "${mc}")" -jar quilt-installer.jar install server "${mc}" "${loader}" --download-server --install-dir="${SERVER_DIR}" \
        || fail "Quilt installer failed"
    rm -f quilt-installer.jar
    mv -f quilt-server-launch.jar "${JARFILE}"
    RESOLVED_VERSION="${mc}"
    ensure_server_properties
    ok "Quilt install complete"
}

install_mohist() {
    local data ver build
    log "Installing Mohist (${MC_VERSION}${BUILD_NUMBER:+ build ${BUILD_NUMBER}})"
    data=$(curl -fsSL -A "${USER_AGENT}" --connect-timeout 30 https://mohistmc.com/api/v2/projects/mohist) \
        || fail "Cannot reach the Mohist API (consider using a DL_URL instead)"
    if [ "${MC_VERSION}" = "latest" ]; then
        ver=$(echo "${data}" | jq -r '.versions[-1]')
    else
        ver=$(echo "${data}" | jq -r --arg v "${MC_VERSION}" '.versions | index($v) as $i | if $i == null then empty else .[$i] end' | head -n1)
        [ -z "${ver}" ] && { warn "No Mohist build for ${MC_VERSION}, defaulting to latest"; ver=$(echo "${data}" | jq -r '.versions[-1]'); }
    fi
    if [ "${BUILD_NUMBER}" = "latest" ]; then
        build=$(curl -fsSL -A "${USER_AGENT}" "https://mohistmc.com/api/v2/projects/mohist/${ver}/builds" | jq -r '.builds[-1].number')
    else
        build=$(curl -fsSL -A "${USER_AGENT}" "https://mohistmc.com/api/v2/projects/mohist/${ver}/builds" | jq -r --arg b "${BUILD_NUMBER}" '[.builds[].number] | index($b) as $i | if $i == null then empty else .[$i] end' | head -n1)
        [ -z "${build}" ] && { warn "Build ${BUILD_NUMBER} not found, using latest"; build=$(curl -fsSL -A "${USER_AGENT}" "https://mohistmc.com/api/v2/projects/mohist/${ver}/builds" | jq -r '.builds[-1].number'); }
    fi
    RESOLVED_VERSION="${ver} (build ${build})"
    log "Downloading Mohist ${ver} build ${build}"
    download "https://mohistmc.com/api/v2/projects/mohist/${ver}/builds/${build}/download" "${JARFILE}"
}

install_magma() {
    local mc="${MC_VERSION}" repo url
    [ "${mc}" = "latest" ] && mc="1.20.1"
    repo="magmamaintained/Magma-${mc}"
    log "Installing Magma from GitHub releases (${repo})"
    url=$(curl -fsSL -A "${USER_AGENT}" "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.assets[]?.browser_download_url | select(endswith(".jar"))' | head -n1)
    [ -z "${url}" ] && fail "No Magma release found for ${mc} (consider using a DL_URL instead)"
    download "${url}" "${JARFILE}"
    RESOLVED_VERSION="${mc}"
}

install_bungeecord() {
    log "Installing BungeeCord (always latest)"
    download "https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/artifact/bootstrap/target/BungeeCord.jar" "${JARFILE}"
    RESOLVED_VERSION="latest"
    ensure_config_yml
    ok "BungeeCord install complete"
}

install_waterfall() {
    install_papermc "waterfall"
    ensure_config_yml
}

install_velocity() {
    install_papermc "velocity"
    ensure_velocity_toml
}

install_bedrock() {
    local url links
    log "Installing Bedrock Dedicated Server (${MC_VERSION})"
    if [ "$(uname -m)" != "x86_64" ]; then
        warn "Mojang only publishes the Bedrock server for x86_64; the build may fail on this architecture"
    fi
    if [ "${MC_VERSION}" = "latest" ]; then
        links=$(curl -fsSL --connect-timeout 30 \
            -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36" \
            -H "Accept-Language: en" \
            https://net-secondary.web.minecraft-services.net/api/v1.0/download/links) \
            || fail "Cannot reach the Bedrock download service"
        url=$(echo "${links}" | grep -o 'https://www.minecraft.net/bedrockdedicatedserver/bin-linux/[^"]*' | head -n1)
        [ -z "${url}" ] && fail "Could not resolve the latest Bedrock server download link"
    else
        url="https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-${MC_VERSION}.zip"
    fi
    log "Downloading ${url}"
    curl -fsSL --retry 3 \
        -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36" \
        -o bedrock.zip "${url}" || fail "Failed to download the Bedrock server"
    unzip -o bedrock.zip > /dev/null
    rm -f bedrock.zip
    chmod +x bedrock_server
    RESOLVED_VERSION=$(echo "${url}" | grep -oP 'bedrock-server-\K[0-9.]+(?=\.zip)' || echo "unknown")
    ensure_server_properties
    ok "Bedrock install complete"
}

install_nukkit() {
    log "Installing Nukkit (always latest)"
    download "https://ci.opencollab.dev/job/NukkitX/job/Nukkit/job/master/lastSuccessfulBuild/artifact/target/nukkit-1.0-SNAPSHOT.jar" "${JARFILE}"
    RESOLVED_VERSION="latest"
    ensure_server_properties
    ok "Nukkit install complete"
}

install_pocketmine() {
    log "Installing PocketMine-MP (always latest)"
    download "https://github.com/pmmp/PocketMine-MP/releases/latest/download/PocketMine-MP.phar" "PocketMine-MP.phar"
    RESOLVED_VERSION="latest"
    ensure_server_properties
    ok "PocketMine-MP install complete"
}

install_github() { # $1 = "check" to only report the upstream state (used by SHOW_VERSIONS-free update probe)
    local data tag asset_url asset_name ref_id prev_repo prev_ref
    GITHUB_REPO="$(normalize_github_repo "${GITHUB_REPO}")"
    [ -n "${GITHUB_REPO}" ] || fail "GITHUB_REPO must be set for the 'github' server type (format: owner/repository or a full GitHub URL)"
    echo "${GITHUB_REPO}" | grep -qE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' \
        || fail "GITHUB_REPO '${GITHUB_REPO}' is not a valid owner/repository (full GitHub URLs and .git suffixes are accepted)"

    # What did this server install last time?
    prev_repo=$(instance_get github_repo)
    prev_ref=$(instance_get github_ref)

    # --- resolve the upstream reference ---------------------------------------
    # 1. A release (tagged or latest) with assets -> download the asset.
    # 2. A tagged commit without a release -> source tarball at that tag.
    # 3. A repo with no releases at all -> source tarball of the default
    #    branch's latest commit ("clone" behaviour for plain code repos).
    data=""
    if [ "${GITHUB_TAG}" = "latest" ]; then
        data=$(gh_api "/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null || true)
    else
        data=$(gh_api "/repos/${GITHUB_REPO}/releases/tags/${GITHUB_TAG}" 2>/dev/null || true)
    fi
    tag=$(echo "${data}" | jq -r '.tag_name // empty' 2>/dev/null)
    asset_url=""
    if [ -n "${tag}" ]; then
        if [ -n "${GITHUB_ASSET}" ]; then
            asset_url=$(echo "${data}" | jq -r --arg a "${GITHUB_ASSET}" '.assets[]?.browser_download_url | select(contains($a))' | head -n1)
        else
            asset_url=$(echo "${data}" | jq -r '.assets[]?.browser_download_url | select(test("\\.jar$"; "i"))' | head -n1)
            [ -z "${asset_url}" ] && asset_url=$(echo "${data}" | jq -r '.assets[0].browser_download_url // empty')
        fi
    fi

    if [ -n "${asset_url}" ] && [ "${asset_url}" != "null" ]; then
        asset_name="${asset_url##*/}"
        ref_id="release:${tag}:${asset_name}"
    else
        # No release/asset: fall back to the repository source archive.
        local branch="${GITHUB_TAG}" sha
        if [ "${branch}" = "latest" ]; then
            branch=$(gh_api "/repos/${GITHUB_REPO}" 2>/dev/null | jq -r '.default_branch // empty' 2>/dev/null)
            [ -z "${branch}" ] \
                && fail "Cannot reach the GitHub API for ${GITHUB_REPO} (check the repository name; set GITHUB_TOKEN for private repositories or when rate-limited)"
        fi
        sha=$(gh_api "/repos/${GITHUB_REPO}/commits/${branch}" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null)
        [ -z "${sha}" ] \
            && fail "Cannot resolve '${branch}' in ${GITHUB_REPO} (invalid tag/branch, or GITHUB_TOKEN is missing/insufficient for a private repository)"
        ref_id="commit:${sha}"
        asset_url=""
        tag="${branch}"
    fi

    # --- update validation: is the installed code still the latest? -----------
    # Release installs require the jar to still be present; source installs
    # count any leftover server content. A missing artifact forces a re-fetch.
    local installed_present=0
    case "${prev_ref}" in
        commit:*) [ -n "$(ls -A "${SERVER_DIR}" 2>/dev/null)" ] && installed_present=1 ;;
        release:*) [ -f "${SERVER_DIR}/${JARFILE}" ] && installed_present=1 ;;
    esac
    if [ -n "${prev_ref}" ] && [ "${prev_repo}" = "${GITHUB_REPO}" ] && [ "${prev_ref}" = "${ref_id}" ] \
        && [ "${installed_present}" = "1" ]; then
        ok "GitHub ${GITHUB_REPO} is already at ${ref_id} - no new commits/releases, nothing to do"
        RESOLVED_VERSION="${ref_id}"
        return 0
    fi
    if [ -n "${prev_ref}" ] && [ "${prev_repo}" = "${GITHUB_REPO}" ]; then
        warn "GitHub update detected: ${prev_ref} -> ${ref_id}"
        ARCHIVE_REASON="github source updated (${prev_ref} -> ${ref_id})"
        archive_previous_instance
    elif [ -n "${prev_ref}" ] && [ -n "${prev_repo}" ] && [ "${prev_repo}" != "${GITHUB_REPO}" ]; then
        warn "GitHub repository changed: ${prev_repo} -> ${GITHUB_REPO}"
        ARCHIVE_REASON="github repository changed (${prev_repo} -> ${GITHUB_REPO})"
        archive_previous_instance
    fi

    # --- fetch ----------------------------------------------------------------
    if [ -n "${asset_url}" ]; then
        log "Downloading ${asset_name} (${GITHUB_REPO} @ ${tag})"
        RESOLVED_VERSION="${tag} (${asset_name})"
        case "${asset_name}" in
            *.zip)
                local tmpzip jar
                tmpzip="${SERVER_DIR}/.gh-asset.zip"
                gh_download "${asset_url}" "${tmpzip}" || { rm -f "${tmpzip}"; fail "Failed to download ${asset_url}"; }
                unzip -o "${tmpzip}" > /dev/null 2>&1 || { rm -f "${tmpzip}"; fail "Release asset ${asset_name} could not be extracted (is it a valid zip?)"; }
                rm -f "${tmpzip}"
                jar=$(ls *.jar 2>/dev/null | grep -v "${JARFILE}" | head -n1)
                [ -z "${jar}" ] && fail "No .jar file found inside the release asset"
                backup_existing_jar
                mv -f "${jar}" "${JARFILE}"
                ;;
            *)
                gh_download "${asset_url}" "${JARFILE}.download.$$" || { rm -f "${JARFILE}.download.$$"; fail "Failed to download ${asset_url}"; }
                backup_existing_jar
                mv -f "${JARFILE}.download.$$" "${JARFILE}" \
                    || { rm -f "${JARFILE}.download.$$"; fail "Could not place the downloaded jar at ${JARFILE}"; }
                ;;
        esac
    else
        local tmpsrc root jar
        log "Fetching repository source (${GITHUB_REPO} @ ${sha})"
        RESOLVED_VERSION="commit ${sha:0:7}"
        tmpsrc="${SERVER_DIR}/.gh-src"
        rm -rf "${tmpsrc}"
        mkdir -p "${tmpsrc}"
        gh_download "https://api.github.com/repos/${GITHUB_REPO}/tarball/${sha}" "${tmpsrc}/src.tar.gz" \
            || { rm -rf "${tmpsrc}"; fail "Failed to download the source archive of ${GITHUB_REPO}"; }
        tar -xzf "${tmpsrc}/src.tar.gz" -C "${tmpsrc}" 2>/dev/null \
            || { rm -rf "${tmpsrc}"; fail "Repository source archive could not be extracted"; }
        rm -f "${tmpsrc}/src.tar.gz"
        root=$(find "${tmpsrc}" -mindepth 1 -maxdepth 1 -type d | head -n1)
        [ -n "${root}" ] || { rm -rf "${tmpsrc}"; fail "Repository source archive is empty"; }
        # Overlay the repo contents into the server directory (non-destructive:
        # anything already present that the archive pass did not move stays).
        (shopt -s dotglob nullglob; cp -a "${root}/"* "${SERVER_DIR}/" 2>/dev/null || true)
        rm -rf "${tmpsrc}"
        jar=$(find "${SERVER_DIR}" -maxdepth 3 -name '*.jar' -not -path "${SERVER_DIR}/archive/*" -not -path "${SERVER_DIR}/.logs/*" -not -name '*-sources*' 2>/dev/null | head -n1)
        if [ -n "${jar}" ] && [ ! -f "${JARFILE}" ]; then
            cp -f "${jar}" "${JARFILE}" 2>/dev/null || true
            log "Using ${jar##*/} as ${JARFILE}"
        fi
        log "Repository source installed into ${SERVER_DIR}"
    fi

    # Record what is installed so the next Reinstall can detect new commits.
    instance_set_kv github_repo "${GITHUB_REPO}"
    instance_set_kv github_ref "${ref_id}"
    ok "GitHub install complete (${GITHUB_REPO} @ ${ref_id})"
}

# ---------------------------------------------------------------------------
# Version listing (SHOW_VERSIONS=1)
# ---------------------------------------------------------------------------
show_versions() {
    local data
    echo "-----------------------------------------"
    echo "Available versions for ${PROJECT_TYPE}:"
    echo "-----------------------------------------"
    case "${PROJECT_TYPE}" in
        vanilla)
            data=$(curl -fsSL -A "${USER_AGENT}" https://piston-meta.mojang.com/mc/game/version_manifest_v2.json)
            echo "Latest release: $(echo "${data}" | jq -r '.latest.release')"
            echo "Latest snapshot: $(echo "${data}" | jq -r '.latest.snapshot')"
            echo "Recent releases:"
            echo "${data}" | jq -r '[.versions[] | select(.type == "release") | .id][0:15][]'
            ;;
        paper | folia | velocity | waterfall)
            data=$(curl -fsSL -A "${USER_AGENT}" "https://fill.papermc.io/v3/projects/${PROJECT_TYPE}")
            echo "${data}" | jq -r '.versions | to_entries[] | "\(.key)  (latest build: \(.value[0]))"'
            ;;
        purpur)
            data=$(curl -fsSL -A "${USER_AGENT}" https://api.purpurmc.org/v2/purpur)
            echo "${data}" | jq -r '.versions | join(", ")'
            ;;
        forge)
            echo "${PROJECT_TYPE} versions:"
            curl -fsSL -A "${USER_AGENT}" https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json \
                | jq -r '.promos | keys[] | select(endswith("-latest")) | rtrimstr("-latest")'
            ;;
        neoforge)
            curl -fsSL -A "${USER_AGENT}" https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml \
                | grep -oP '(?<=<version>)[^<]+' | sort -V | tail -n15
            ;;
        mohist)
            data=$(curl -fsSL -A "${USER_AGENT}" --connect-timeout 30 https://mohistmc.com/api/v2/projects/mohist 2>/dev/null) \
                && echo "${data}" | jq -r '.versions | join(", ")' || echo "(Mohist API unreachable)"
            ;;
        github)
            echo "GitHub releases are listed at https://github.com/${GITHUB_REPO}/releases"
            ;;
        *)
            echo "No version listing available for ${PROJECT_TYPE}."
            ;;
    esac
    echo "-----------------------------------------"
    exit 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Version listing mode: show what is available and stop.
if [ "${SHOW_VERSIONS}" = "1" ]; then
    show_versions
fi

run_install() {

    # --- normalize version keywords: latest / stable / snapshot / alpha ... ---
    case "$(echo "${MC_VERSION}" | tr '[:upper:]' '[:lower:]')" in
        latest|stable|release|ga|production)
            MC_VERSION="latest"
            ;;
        snapshot|alpha|beta|experimental|nightly|preview|dev)
            MC_VERSION="latest-snapshot"
            ;;
    esac
    case "${MC_VERSION}" in
        latest|latest-snapshot) ;;
        *)
            if ! echo "${MC_VERSION}" | grep -qE '^[A-Za-z0-9._-]+$'; then
                warn "'${MC_VERSION}' is not a valid version identifier; falling back to latest"
                MC_VERSION="latest"
            fi
            ;;
    esac

    # --- instance change detection: never lose data on type/version switches ---
    PREV_TYPE=$(instance_get type)
    PREV_MC=$(instance_get mc_version)
    PREV_RESOLVED=$(instance_get resolved_version)
    ARCHIVE_REASON=""
    local archive_needed=0
    if [ -n "${PREV_TYPE}" ]; then
        if [ "${PREV_TYPE}" != "${PROJECT_TYPE}" ]; then
            archive_needed=1
            ARCHIVE_REASON="server type changed (${PREV_TYPE} -> ${PROJECT_TYPE})"
        else
            local pline cline
            pline=$(major_line "${PREV_RESOLVED}")
            [ -z "${pline}" ] && pline=$(major_line "${PREV_MC}")
            cline=$(major_line "${MC_VERSION}")
            if [ -n "${pline}" ] && [ -n "${cline}" ] && [ "${pline}" != "${cline}" ]; then
                archive_needed=1
                ARCHIVE_REASON="minecraft major version line changed (${pline}.x -> ${cline}.x)"
            elif [ -n "${PREV_MC}" ] && [ "${PREV_MC}" != "${MC_VERSION}" ] && { [ "${MC_VERSION}" = "latest-snapshot" ] || [ "${PREV_MC}" = "latest-snapshot" ]; }; then
                archive_needed=1
                ARCHIVE_REASON="snapshot channel switched (${PREV_MC} -> ${MC_VERSION})"
            fi
        fi
    fi
    if [ "${archive_needed}" = "1" ]; then
        archive_previous_instance
    else
        [ -n "${PREV_TYPE}" ] && log "No breaking changes detected - existing worlds/configs are kept as-is"
    fi

    # --- AUTO_UPDATE=0: do nothing when the server files are already present ---
    if [ "${AUTO_UPDATE}" = "0" ]; then
        local target="${JARFILE}"
        case "${PROJECT_TYPE}" in
            bedrock) target="bedrock_server" ;;
            pocketmine) target="PocketMine-MP.phar" ;;
        esac
        if [ -f "${SERVER_DIR}/${target}" ]; then
            ok "AUTO_UPDATE=0 and '${target}' already present - skipping installation"
            exit 0
        fi
        log "AUTO_UPDATE=0 but '${target}' is missing - performing first installation"
    fi

    # A custom download URL bypasses all project logic for Java server types.
    if [ -n "${DL_URL:-}" ] && [ "${PROJECT_TYPE}" != "custom" ] \
        && [ "${PROJECT_TYPE}" != "bedrock" ] && [ "${PROJECT_TYPE}" != "pocketmine" ]; then
        log "Using custom download URL (bypassing ${PROJECT_TYPE} project logic)"
        download "${DL_URL}" "${JARFILE}"
        exit 0
    fi

    case "${PROJECT_TYPE}" in
        vanilla)     install_vanilla ;;
        paper)       install_papermc "paper" ;;
        folia)       install_papermc "folia" ;;
        purpur)      install_purpur ;;
        spigot)      install_spigot ;;
        forge)       install_forge ;;
        neoforge)    install_neoforge ;;
        fabric)      install_fabric ;;
        quilt)       install_quilt ;;
        mohist)      install_mohist ;;
        magma)       install_magma ;;
        bungeecord)  install_bungeecord ;;
        waterfall)   install_waterfall ;;
        velocity)    install_velocity ;;
        bedrock)     install_bedrock ;;
        nukkit)      install_nukkit ;;
        pocketmine)  install_pocketmine ;;
        github)      install_github ;;
        custom)
            if [ -n "${DL_URL:-}" ]; then
                log "Downloading custom server files from DL_URL"
                case "${DL_URL}" in
                    *.zip)
                        curl -fsSL --retry 3 --connect-timeout 20 -A "${USER_AGENT}" -o /tmp/custom.zip "${DL_URL}" || fail "Failed to download custom zip"
                        unzip -o /tmp/custom.zip -d "${SERVER_DIR}" > /dev/null 2>&1
                        rm -f /tmp/custom.zip
                        local jar
                        jar=$(ls *.jar 2>/dev/null | grep -v "${JARFILE}" | head -n1)
                        if [ -n "${jar}" ] && [ ! -f "${JARFILE}" ]; then
                            mv "${jar}" "${JARFILE}"
                        fi
                        log "Extracted custom zip archive"
                        ;;
                    *.tar.gz | *.tgz)
                        curl -fsSL --retry 3 --connect-timeout 20 -A "${USER_AGENT}" -o /tmp/custom.tar.gz "${DL_URL}" || fail "Failed to download custom tar.gz"
                        tar -xzf /tmp/custom.tar.gz -C "${SERVER_DIR}" > /dev/null 2>&1
                        rm -f /tmp/custom.tar.gz
                        local jar
                        jar=$(ls *.jar 2>/dev/null | grep -v "${JARFILE}" | head -n1)
                        if [ -n "${jar}" ] && [ ! -f "${JARFILE}" ]; then
                            mv "${jar}" "${JARFILE}"
                        fi
                        log "Extracted custom tar.gz archive"
                        ;;
                    *)
                        download "${DL_URL}" "${JARFILE}"
                        ;;
                esac
            else
                log "Custom server type: nothing to download (set DL_URL or upload your own files)"
            fi
            ;;
        *) fail "Unknown server type: ${PROJECT_TYPE}" ;;
    esac

    # Ensure a server.properties exists for Java servers so the panel can
    # configure the port automatically (proxies/BDS generate their own files).
    case "${PROJECT_TYPE}" in
        paper|folia|purpur|spigot|forge|neoforge|fabric|quilt|mohist|magma|nukkit|github|custom)
            ensure_server_properties ;;
    esac

    # Extra files (plugins, configs, resource packs, ...) and world import.
    install_extra_urls
    install_world

    # Record the installed instance so future type/version switches are safe.
    instance_set_kv type "${PROJECT_TYPE}"
    instance_set_kv mc_version "${MC_VERSION}"
    [ -n "${RESOLVED_VERSION}" ] && instance_set_kv resolved_version "${RESOLVED_VERSION}"
    instance_set_kv java "$(java_for_mc "${MC_VERSION}")"
    instance_set_kv updated "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    echo "-----------------------------------------"
    echo -e "\033[1m\033[32mInstallation completed successfully\033[0m"
    echo "-----------------------------------------"
    echo -e "\033[36m  Server type :\033[0m ${PROJECT_TYPE}"
    [ -n "${RESOLVED_VERSION}" ] && echo -e "\033[36m  Version     :\033[0m ${RESOLVED_VERSION}"
    echo -e "\033[36m  Java        :\033[0m $(java_for_mc "${MC_VERSION}") (auto-selected at runtime)"
    echo -e "\033[36m  Jar file    :\033[0m ${JARFILE}"
    echo "-----------------------------------------"
    echo -e "\033[1;33mNext steps:\033[0m"
    echo "  1. Start the server in the panel and accept the EULA when prompted."
    echo "  2. Players connect to: ${SERVER_IP:-<node IP>}:${SERVER_PORT:-25565}"
    echo "  3. Change settings in the panel (Variables) and press Reinstall to update."
    echo -e "\033[2;37m  Full installer trace: install-error.log (crash history: error.log)\033[0m"
    echo "-----------------------------------------"
}

# ---------------------------------------------------------------------------
# Traced execution: a full xtrace of every step is written to
# install-error.log. On failure the console prints a report plus the last
# trace lines, so troubleshooting never requires re-running with DEBUG.
# ---------------------------------------------------------------------------
ERROR_LOG="${SERVER_DIR}/install-error.log"

log_rotate_file() { # keep the log bounded (~512 KB)
    local max=524288
    [ -f "$1" ] || return 0
    [ "$(wc -c < "$1" 2>/dev/null || echo 0)" -le "$max" ] || mv -f "$1" "$1.old" 2>/dev/null || true
}

log_event() {
    printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "${ERROR_LOG}" 2>/dev/null || true
}

log_rotate_file "${ERROR_LOG}"
log_event "=== install started: type=${PROJECT_TYPE} mc=${MC_VERSION} build=${BUILD_NUMBER} loader=${LOADER_VERSION} auto_update=${AUTO_UPDATE} ==="

if [ "${DEBUG:-0}" != "1" ]; then
    exec {MMC_TRACE_FD}>>"${ERROR_LOG}"
    BASH_XTRACEFD="${MMC_TRACE_FD}"
    PS4='+[${EPOCHREALTIME:-$SECONDS}] ${BASH_SOURCE##*/}:${LINENO} ${FUNCNAME[0]:-main}(): '
    set -x
fi

( run_install )
STATUS=$?
if [ "${DEBUG:-0}" != "1" ]; then
    set +x 2>/dev/null || true
fi

if [ "${STATUS}" -eq 0 ]; then
    log_event "=== install finished successfully ==="
    exit 0
fi

log_event "=== install FAILED (exit ${STATUS}) ==="
echo ""
echo -e "\033[1;31m==============================================================\033[0m"
echo -e "\033[1;31m  INSTALLATION FAILED (exit code: ${STATUS})\033[0m"
echo -e "\033[1;31m==============================================================\033[0m"
echo -e "  \033[1;33mFull execution trace saved to:\033[0m ${ERROR_LOG}"
echo -e "\033[2;37m--------------------------------------------------------------\033[0m"
tail -n 40 "${ERROR_LOG}" 2>/dev/null | sed 's/^/  /'
echo -e "\033[2;37m--------------------------------------------------------------\033[0m"
echo -e "  \033[1;33mTips: set SHOW_VERSIONS=1 to list valid versions for\033[0m"
echo -e "  \033[1;33m'${PROJECT_TYPE}', or DEBUG=1 for console-level tracing.\033[0m"
exit "${STATUS}"