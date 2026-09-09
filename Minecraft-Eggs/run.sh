#!/bin/bash
#
# Multi Minecraft - universal server launcher
#
# This script is the single entry point for every server type the egg
# supports. It dispatches to the right binary based on the SERVER_TYPE
# environment variable that the panel injects (or that was persisted in
# .multi-mc.conf on first run).
#
# Panel Stop contract (works on Pterodactyl, Pelican, Feather, Jexactyl,
# Wisp, PufferPanel and plain Docker):
#   1. Console command text ("stop"/"^C"/"end"...) is caught by the stdin
#      stop-command watcher and triggers a graceful shutdown. Non-stop console
#      lines are forwarded to the server console, so in-game commands typed in
#      the panel keep working.
#   2. Real signals (SIGTERM/SIGINT/SIGHUP) land on this launcher (PID 1)
#      and trigger the same graceful shutdown (JVM shutdown hooks / proxies).
#   3. A server that ignores everything is force-killed after the grace
#      window, and a container-wide sweep removes orphaned children that
#      escaped the process tree - the panel never hangs on "stopping".
#
# Environment variables consumed (injected by the panel / egg):
#   SERVER_TYPE      vanilla|paper|spigot|purpur|folia|forge|neoforge|fabric|
#                    quilt|mohist|magma|bungeecord|velocity|waterfall|bedrock|
#                    nukkit|pocketmine|github|custom
#   SERVER_JARFILE   jar file name to launch (Java servers)
#   SERVER_MEMORY    allocated memory in MB (Java servers)
#   JAVA_FLAGS       JVM arguments (default: Aikar's tuned G1GC set;
#                    empty = GC_TYPE picks the tuning)
#   GC_TYPE          auto|g1gc|zgc|parallel (used when JAVA_FLAGS is empty)
#   EXTRA_ARGS       extra arguments appended after the jar (e.g. --nogui)
#   CUSTOM_COMMAND   raw command to execute when SERVER_TYPE=custom
#   PANEL_STOP_WATCHER auto|0|1 : console stop-command watcher toggle
#
# Optional escape hatch: if a file named "run.custom.sh" exists in the server
# directory it is executed instead of the logic below. All environment
# variables above remain available.

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

phase() { printf "\n%b── %s %b\n" "${C_DIM}" "$*" "────────────────────────────────────────────────${C_RESET}"; }

PANEL_TYPE="${PANEL_TYPE:-Docker / Standalone}"

# --- Troubleshooting infrastructure ---------------------------------------------
# _egg_error_log(): append-only error journal (launcher failures, crashes,
# sweeps) at .logs/launcher-errors.log so failures can be diagnosed after the
# fact even when panel scrollback is gone. The entrypoint appends here too.
ERROR_LOG=""
_egg_error_log() {
    if [ -z "${ERROR_LOG}" ]; then
        local d="${SERVER_DIR:-${PWD}}/.logs"
        if mkdir -p "${d}" 2>/dev/null && [ -w "${d}" ]; then
            ERROR_LOG="${d}/launcher-errors.log"
        else
            ERROR_LOG="/tmp/potenfyr-errors.log"
        fi
        if [ -f "${ERROR_LOG}" ] && [ "$(wc -c < "${ERROR_LOG}" 2>/dev/null || echo 0)" -gt 524288 ]; then
            mv -f "${ERROR_LOG}" "${ERROR_LOG}.old" 2>/dev/null || true
        fi
    fi
    printf '[%s] [%s] [panel=%s] %s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)" \
        "${1:-launcher}" "${PANEL_TYPE:-unknown}" "${2:-unknown}" \
        >> "${ERROR_LOG}" 2>/dev/null || true
}

if [ "${CLI_THEME}" = "classic" ]; then
    log()   { printf "%b %b\n" "${C_CYAN}${C_BOLD}[PotenFYR]${C_RESET}" "$*"; }
    ok()    { printf "%b %b\n" "${C_GREEN}${C_BOLD}[PotenFYR][✓]${C_RESET}" "$*"; }
    warn()  { printf "%b %b\n" "${C_YELLOW}${C_BOLD}[PotenFYR][!]${C_RESET}" "${C_YELLOW}$*${C_RESET}"; }
    error() { printf "%b %b\n" "${C_RED}${C_BOLD}[PotenFYR][✗]${C_RESET}" "${C_RED}$*${C_RESET}"; _egg_error_log "launcher" "$*"; }
    info()  { printf "%b %b\n" "${C_BLUE}${C_BOLD}[PotenFYR][i]${C_RESET}" "$*"; }
else
    log()   { printf "%b %b\n" "${C_LIME}${C_BOLD}</> multi-minecraft${C_RESET}${C_DIM} ▸${C_RESET}" "$*"; }
    ok()    { printf "%b %b\n" "${C_LIME}${C_BOLD}</> multi-minecraft ✔${C_RESET}" "${C_GREEN}$*${C_RESET}"; }
    warn()  { printf "%b %b\n" "${C_GOLD}${C_BOLD}</> multi-minecraft ⚠${C_RESET}" "${C_YELLOW}$*${C_RESET}"; }
    error() { printf "%b %b\n" "${C_RED}${C_BOLD}</> multi-minecraft ✖${C_RESET}" "${C_RED}$*${C_RESET}"; _egg_error_log "launcher" "$*"; }
    info()  { printf "%b %b\n" "${C_CYAN}${C_BOLD}</> multi-minecraft ℹ${C_RESET}" "$*"; }
fi

if [ -d /home/container ]; then
    cd /home/container 2>/dev/null || true
else
    cd "$(pwd)" 2>/dev/null || true
fi
SERVER_DIR="$(pwd)"

# --- Security baseline ----------------------------------------------------------
# No world-writable files from the launcher; no core dumps eating disk space.
umask 022
ulimit -c 0 2>/dev/null || true

# Ensure Java runtime is in PATH even if run.sh is invoked directly
if ! command -v java >/dev/null 2>&1; then
    for cand in /opt/java/*/bin/java ~/.java/*/bin/java ./java/bin/java; do
        if [ -x "${cand}" ]; then
            JAVA_BIN_DIR="$(dirname "${cand}")"
            export PATH="${JAVA_BIN_DIR}:${PATH}"
            export JAVA_HOME="$(dirname "${JAVA_BIN_DIR}")"
            break
        fi
    done
fi

# --- Persisted settings ------------------------------------------------------
CONF_FILE="${CONF_FILE:-${SERVER_DIR}/.multi-mc.conf}"

write_conf() { # key value : upsert a KEY=VALUE line (no shell evaluation on read)
    local key="$1" value="$2" tmp
    tmp="$(mktemp)"
    if [ -f "${CONF_FILE}" ]; then
        awk -v k="${key}" -v v="${value}" \
            'BEGIN { FS = "="; OFS = "=" }
             $1 == k { found = 1; print k, v; next }
             { print }
             END { if (!found) print k, v }' "${CONF_FILE}" > "${tmp}"
    else
        printf '%s=%s\n' "${key}" "${value}" > "${tmp}"
    fi
    mv "${tmp}" "${CONF_FILE}"
    chmod 600 "${CONF_FILE}" 2>/dev/null || true
}

VALID_TYPES="vanilla paper spigot purpur folia forge neoforge fabric quilt mohist magma bungeecord velocity waterfall bedrock nukkit pocketmine github custom"

is_valid_type() { case " ${VALID_TYPES} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ---------------------------------------------------------------------------
# Validation & defaults (auto-fill empty values)
# ---------------------------------------------------------------------------
TYPE=$(echo "${SERVER_TYPE:-vanilla}" | tr '[:upper:]' '[:lower:]')

phase "Server Configuration"
_egg_error_log "launcher" "=== launch: type=${TYPE} mc=${MINECRAFT_VERSION:-latest} mem=${SERVER_MEMORY:-1024} java=${JAVA_VERSION:-auto} ==="
# Only log abnormal exits; graceful stops (0,130,143) are not errors
trap 'ec=$?; if [ "${ec}" -ne 0 ] && [ "${ec}" -ne 130 ] && [ "${ec}" -ne 143 ]; then _egg_error_log "launcher" "launcher terminated abnormally (code ${ec})"; fi' EXIT
[ -z "${TYPE}" ] && TYPE="vanilla"

if ! is_valid_type "${TYPE}"; then
    warn "Server type '${TYPE}' is not supported by this egg; defaulting to 'vanilla'."
    TYPE="vanilla"
    write_conf SERVER_TYPE "${TYPE}"
    export SERVER_TYPE="${TYPE}"
fi

MINECRAFT_VERSION="${MINECRAFT_VERSION:-latest}"
[ -z "${MINECRAFT_VERSION}" ] && MINECRAFT_VERSION="latest"

if [ "${TYPE}" = "custom" ] && [ -z "${CUSTOM_COMMAND:-}" ]; then
    CUSTOM_COMMAND="java -Xms128M -Xmx${SERVER_MEMORY:-1024}M -jar ${SERVER_JARFILE:-server.jar}"
    write_conf CUSTOM_COMMAND "${CUSTOM_COMMAND}"
    export CUSTOM_COMMAND="${CUSTOM_COMMAND}"
fi

if [ -n "${JAVA_VERSION:-}" ]; then
    if ! echo "${JAVA_VERSION}" | grep -qE '^(https?://[A-Za-z0-9._~:/?#\[\]@!$&'\''()*+,;=%-]+|[A-Za-z0-9_.-]+)$'; then
        warn "JAVA_VERSION '${JAVA_VERSION}' has an invalid format; using auto-detection."
        unset JAVA_VERSION
    fi
fi

if [ "${DEBUG:-0}" = "1" ]; then
    log "DEBUG: TYPE=${TYPE} MC=${MINECRAFT_VERSION:-} BUILD=${BUILD_NUMBER:-} LOADER=${LOADER_VERSION:-}"
    log "DEBUG: JAR=${SERVER_JARFILE:-server.jar} JAVA=${JAVA_VERSION:-auto} MEM=${SERVER_MEMORY:-1024}"
    log "DEBUG: CONF_FILE=${CONF_FILE} GC=${GC_TYPE:-auto}"
fi

# User-provided launcher override (ultimate escape hatch).
if [ -f ./run.custom.sh ]; then
    exec bash ./run.custom.sh
fi

SERVER_PORT="${SERVER_PORT:-${PORT:-${ALLOCATION_PORT:-${SERVER_PORT_0:-25565}}}}"
SERVER_MEMORY="${SERVER_MEMORY:-${MEMORY:-${MEM_SIZE:-${P_SERVER_MEMORY:-1024}}}}"
SERVER_IP="${SERVER_IP:-${IP:-${P_SERVER_IP:-0.0.0.0}}}"
SERVER_JARFILE="${SERVER_JARFILE:-${JARFILE:-server.jar}}"
MEMORY=${SERVER_MEMORY}

# ---------------------------------------------------------------------------
# Auto-installation if server files are not found
# ---------------------------------------------------------------------------
auto_install_if_needed() {
    local need_install=0
    case "${TYPE}" in
        bedrock)
            [ ! -f ./bedrock_server ] && need_install=1
            ;;
        pocketmine)
            [ ! -f ./PocketMine-MP.phar ] && need_install=1
            ;;
        *)
            if [ ! -f "${SERVER_JARFILE:-server.jar}" ] && [ ! -f unix_args.txt ]; then
                local cand_jar
                cand_jar=$(ls *.jar 2>/dev/null | grep -v 'installer' | head -n1)
                if [ -n "${cand_jar}" ]; then
                    SERVER_JARFILE="${cand_jar}"
                else
                    need_install=1
                fi
            fi
            ;;
    esac

    if [ "${need_install}" = "1" ]; then
        phase "Auto-Install"
        log "Server files not found in $(pwd). Running automatic installation for ${TYPE} (${MINECRAFT_VERSION})..."
        if [ -x /opt/potenfyr/install.sh ]; then
            bash /opt/potenfyr/install.sh || warn "Installer exited with code $?"
        elif [ -x /usr/local/bin/install.sh ]; then
            bash /usr/local/bin/install.sh || warn "Installer exited with code $?"
        elif [ -f ./install.sh ]; then
            bash ./install.sh || warn "Installer exited with code $?"
        elif [ -x /install.sh ]; then
            bash /install.sh || warn "Installer exited with code $?"
        elif command -v install.sh >/dev/null 2>&1; then
            install.sh || warn "Installer exited with code $?"
        fi
    fi
}

auto_install_if_needed

# ---------------------------------------------------------------------------
# Automated crash diagnostics (defined BEFORE first use)
# ---------------------------------------------------------------------------
print_crash_diagnostics() {
    local code="$1"
    local divider
    divider=$(printf '%*s' 62 '' | tr ' ' '=')
    local sub_divider
    sub_divider=$(printf '%*s' 62 '' | tr ' ' '-')

    printf "\n${C_RED}${C_BOLD}%s${C_RESET}\n" "${divider}"
    printf "${C_RED}${C_BOLD}  [CRASH DETECTED] Server process terminated abnormally (Exit code: %s)${C_RESET}\n" "${code}"
    printf "${C_RED}${C_BOLD}%s${C_RESET}\n" "${divider}"

    printf "  ${C_YELLOW}${C_BOLD}Context Summary:${C_RESET}\n"
    printf "  • Software   : %s (%s)\n" "${TYPE}" "${MINECRAFT_VERSION:-latest}"
    printf "  • Java       : %s\n" "$(java -version 2>&1 | head -n1 || echo 'Java not found')"
    printf "  • Memory     : %s MB\n" "${SERVER_MEMORY:-1024}"
    printf "  • Directory  : %s\n" "${SERVER_DIR:-$(pwd)}"
    printf "  • Disk Free  : %s\n" "$(df -h . 2>/dev/null | awk 'NR==2 {print $4}' || echo 'unknown')"

    printf "${C_DIM}%s${C_RESET}\n" "${sub_divider}"
    printf "  ${C_GREEN}${C_BOLD}Automated Diagnostics:${C_RESET}\n"

    # 1. Check EULA
    if [ -f eula.txt ] && grep -qi "eula=false" eula.txt; then
        printf "  ${C_YELLOW}⚠ EULA Not Accepted:${C_RESET} eula.txt contains eula=false. Accept EULA in panel or set eula=true.\n"
    elif [ ! -f eula.txt ] && [ "${TYPE}" != "bedrock" ] && [ "${TYPE}" != "pocketmine" ] && [ "${TYPE}" != "velocity" ] && [ "${TYPE}" != "waterfall" ] && [ "${TYPE}" != "bungeecord" ]; then
        printf "  ${C_YELLOW}⚠ EULA Missing:${C_RESET} Server exited on initial startup to generate eula.txt. Accept EULA and start again.\n"
    fi

    # 2. Check Out of Memory
    if [ "${code}" -eq 137 ]; then
        printf "  ${C_RED}⚠ Out Of Memory (OOM Killer):${C_RESET} Container exceeded memory limit (${SERVER_MEMORY:-1024} MB). Increase server memory in panel.\n"
    fi

    # 3. Check for crash reports / latest logs
    if [ -d crash-reports ]; then
        local latest_crash
        latest_crash=$(ls -t crash-reports/crash-*.txt 2>/dev/null | head -n1)
        if [ -n "${latest_crash}" ]; then
            printf "  ${C_YELLOW}⚠ Crash Report Found:${C_RESET} %s\n" "${latest_crash}"
            printf "  ${C_DIM}----------------------------------------${C_RESET}\n"
            grep -E '^(Description|Caused by|java\.lang\.)' "${latest_crash}" 2>/dev/null | head -n6 | sed 's/^/    /'
            printf "  ${C_DIM}----------------------------------------${C_RESET}\n"
        fi
    elif [ -f logs/latest.log ]; then
        local error_lines
        error_lines=$(grep -iE '(error|exception|fatal|failed)' logs/latest.log 2>/dev/null | tail -n5)
        if [ -n "${error_lines}" ]; then
            printf "  ${C_YELLOW}⚠ Recent Errors in logs/latest.log:${C_RESET}\n"
            printf "${C_DIM}%s${C_RESET}\n" "${error_lines}" | sed 's/^/    /'
        fi
    fi

    # 4. Recent console output (from the .logs/console.log mirror, if present)
    local _clog="${SERVER_DIR}/.logs/console.log"
    if [ -f "${_clog}" ]; then
        printf "${C_DIM}  ▼ last 12 console lines before the crash (%s):${C_RESET}\n" "${_clog}"
        tail -n 12 "${_clog}" 2>/dev/null | sed 's/^/  | /'
        printf "\n"
    fi

    printf "${C_DIM}%s${C_RESET}\n" "${sub_divider}"
    printf "  ${C_GREEN}${C_BOLD}Next Steps to Resolve:${C_RESET}\n"
    printf "  1. Inspect full log output above for specific mod/plugin incompatibilities.\n"
    printf "  2. If Java version mismatch occurs, select compatible JAVA_VERSION in panel Variables.\n"
    printf "  3. Trigger 'Reinstall Server' if server files or libraries are corrupted.\n"
    printf "  4. Full launcher/crash history is saved in .logs/launcher-errors.log (panel File Manager).\n"
    printf "${C_RED}${C_BOLD}%s${C_RESET}\n\n" "${divider}"
}

# ---------------------------------------------------------------------------
# Graceful shutdown machinery (fixes stop/restart hanging on ALL panels)
# ---------------------------------------------------------------------------
# Panels stop servers in up to four ways, and ALL of them are handled here:
#   1. Console command text on stdin ("stop"/"^C"/"end") - the stdin watcher
#      below catches it (Wings-family daemons deliver stop as TEXT, Feather
#      Panel included; Tty:true containers included).
#   2. Real signals (SIGTERM/SIGINT) from panels and docker stop - traps below.
#   3. A hung server that ignores console+SIGTERM - grace timer escalates to a
#      full process-tree kill within the panel's force-kill window.
#   4. Detached/double-forked strays - container-wide sweep on stop.
SERVER_PID=""
TRANSLATOR_PID=""
STOP_WATCHER_PID=0
FIFO_PATH="/tmp/mc-stdin.fifo"
EXIT_STATUS=0
SHUTDOWN_INITIATED=0

# Recursively list all descendant PIDs of a process (children, grandchildren,
# double-forked strays still inside the tree).
get_all_child_pids() {
    local parent="$1"
    [ -z "${parent}" ] && return 0
    local children
    children=$(pgrep -P "${parent}" 2>/dev/null || true)
    if [ -z "${children}" ] && [ -d "/proc" ]; then
        children=$(awk -v p="${parent}" '$1 == "PPid:" && $2 == p {print FILENAME}' /proc/[0-9]*/status 2>/dev/null | awk -F/ '{print $3}' || true)
    fi
    for child in ${children}; do
        get_all_child_pids "${child}"
        echo "${child}"
    done
}

# Terminate a process and its full tree: TERM+INT, poll up to N seconds at
# 0.2s intervals, then SIGKILL anything still alive. Non-fatal by design.
terminate_process_tree() {
    local root_pid="$1"
    local timeout="${2:-5}"
    [ -n "${root_pid}" ] || return 0
    [ "${root_pid}" -gt 1 ] 2>/dev/null || return 0
    kill -0 "${root_pid}" 2>/dev/null || return 0

    local pids waited=0 max_wait=$((timeout * 5))
    pids="$(get_all_child_pids "${root_pid}") ${root_pid}"
    for p in ${pids}; do
        kill -TERM "${p}" 2>/dev/null || true
        kill -INT "${p}" 2>/dev/null || true
    done
    while kill -0 "${root_pid}" 2>/dev/null && [ "${waited}" -lt $((timeout * 5)) ]; do
        sleep 0.2
        waited=$((waited + 1))
    done
    if kill -0 "${root_pid}" 2>/dev/null; then
        pids="$(get_all_child_pids "${root_pid}") ${root_pid}"
        for p in ${pids}; do
            kill -KILL "${p}" 2>/dev/null || true
        done
        sleep 0.3
    fi
    wait "${root_pid}" 2>/dev/null || true
}

# Container-wide sweep for orphaned processes (detached daemons, double-forked
# workers, background spawners) that escaped every tracked process tree - they
# keep serving even after the main server dies and the panel shows "stopping".
#   sweep_stray_processes graceful -> TERM, wait, escalate to KILL (panel stop)
#   sweep_stray_processes quick    -> immediate SIGKILL (pre-start port cleanup)
# Excludes: the launcher shell itself, console-mirror helpers, stdin watcher.
sweep_stray_processes() {
    local mode="${1:-graceful}" _me="$$" _p _name _killed=0
    [ -d "/proc" ] || return 0
    for _p in $(ps -eo pid=,ppid= 2>/dev/null | awk -v me="${_me}" '$2 == 1 && $1 != me {print $1}'); do
        [ -n "${_p}" ] && [ "${_p}" -gt 1 ] 2>/dev/null || continue
        [ "${_p}" = "${STOP_WATCHER_PID:-0}" ] && continue
        _name="$(ps -o comm= -p "${_p}" 2>/dev/null || echo '')"
        case "${_name}" in
            tee|stdbuf|ps|awk|sed|grep) continue ;;
        esac
        if [ "${mode}" = "quick" ]; then
            kill -9 "${_p}" 2>/dev/null || true
        else
            terminate_process_tree "${_p}" 2
        fi
        _killed=$((_killed + 1))
    done
    if [ "${_killed}" -gt 0 ]; then
        log "Swept ${_killed} stray process(es) (detached daemons / double-forked workers)."
        _egg_error_log "launcher" "swept ${_killed} stray process(es) during ${mode} sweep" || true
    fi
    return 0
}

# Send stop command to the server console (FIFO mode) or SIGTERM the process

# Send stop command to the server console (FIFO mode) or SIGTERM the process
# (direct-stdin mode). Only arms the shutdown timer - the wait loop enforces
# the grace period, SIGTERM escalation and SIGKILL.
send_stop_command() {
    if [ -p "${FIFO_PATH:-}" ] && [ -n "${SERVER_PID}" ]; then
        case "${TYPE}" in
            bungeecord|waterfall|velocity) printf 'end\n' >&5 2>/dev/null || true ;;
            *) printf 'stop\n' >&5 2>/dev/null || true ;;
        esac
    elif [ -n "${SERVER_PID}" ] && kill -0 "${SERVER_PID}" 2>/dev/null; then
        # No FIFO (direct-stdin servers): SIGTERM triggers the JVM shutdown
        # hooks, which save the world and stop the server cleanly.
        kill -TERM "${SERVER_PID}" 2>/dev/null || true
    fi
}

# Signal handler: request graceful shutdown.
#
# IMPORTANT: this handler must NOT block. It only arms the shutdown (sets
# SHUTDOWN_INITIATED=1 and nudges the server); the wait loop below enforces
# the grace period, SIGTERM escalation and SIGKILL. If the handler itself
# waited on the server, a server that ignores the stop command would keep the
# launcher blocked inside the trap - the panel would sit on "stopping" forever
# while the server keeps running (exactly the bug this fixes).
handle_signal() {
    local sig="$1"
    if [ "${SHUTDOWN_INITIATED}" -eq 1 ]; then
        return
    fi
    SHUTDOWN_INITIATED=1
    log "Received ${sig}, initiating graceful shutdown..."
    # Stop the stdin watcher: it has done its job and must not re-trigger or
    # race the FIFO shutdown write below.
    if [ -n "${STOP_WATCHER_PID}" ] && [ "${STOP_WATCHER_PID}" -gt 1 ] 2>/dev/null; then
        kill -9 "${STOP_WATCHER_PID}" 2>/dev/null || true
        STOP_WATCHER_PID=0
    fi
    send_stop_command || true
}

trap 'handle_signal TERM' TERM
trap 'handle_signal INT' INT
trap 'handle_signal HUP' HUP
trap 'handle_signal QUIT' QUIT
trap - EXIT

# --- Console mirror drain ------------------------------------------------------
# The entrypoint mirrors the whole console through a `tee` child process
# (exec > >(tee -a .logs/console.log)). tee exits only when our stdout closes,
# i.e. when this launcher exits - and when PID 1 exits the kernel SIGKILLs the
# whole PID namespace immediately, so a launcher that prints a large block and
# exits right away (crash report, stop confirmation) can get the tail of its
# output cut off from docker/panel logs. The EXIT trap below gives the mirror
# a brief drain window while the container is still alive. No-op when the
# mirror is disabled (LAUNCHER_LOG=0) or no tee child exists.
mirror_drain() {
    local d ppid name
    for d in /proc/[0-9]*; do
        [ -r "${d}/status" ] || continue
        ppid=$(awk '/^PPid:/{print $2}' "${d}/status" 2>/dev/null)
        [ "${ppid}" = "$$" ] || continue
        name=$(awk '/^Name:/{print $2}' "${d}/status" 2>/dev/null)
        [ "${name}" = "tee" ] || continue
        sleep "${CONSOLE_DRAIN_SECONDS:-0.5}"
        return 0
    done
    return 0
}
trap 'mirror_drain' EXIT

# --- Panel Stop Command Watcher (stdin) ---------------------------------------
# Wings-family daemons (Feather Panel, Pterodactyl, Pelican, Jexactyl, Wisp)
# create server containers with Tty:true and deliver the configured stop
# command ("^C" etc.) as console TEXT on that TTY stdin instead of raising a
# signal. The literal text "^C" is not a real INTR byte, so the kernel never
# generates SIGINT, and without a reader the stop line just sits in the tty
# input buffer while the panel hangs on "stopping" until the daemon times out
# and force-kills the container. This watcher scans console input (pipe OR
# tty) and raises our own shutdown trap when a stop command is seen; every
# other line is forwarded verbatim to the server console (FIFO), so regular
# in-game console commands keep working. The watcher is the SINGLE reader of
# panel stdin - the server console reads the FIFO instead - so console lines
# are never raced or lost.
# PANEL_STOP_WATCHER=0 disables the watcher entirely; =1 forces it on.

panel_stop_watcher() {
    local line trimmed
    # Reads fd 3, a dup of the console stdin taken in the main shell below, so
    # the watcher never races the main shell for fd 0 itself. Forwards every
    # non-stop line into the server console FIFO (fd 5).
    while IFS= read -r -u 3 line || [ -n "${line}" ]; do
        trimmed="${line}"
        trimmed="${trimmed//$'\r'/}"
        trimmed="${trimmed//[[:space:]]/}"
        trimmed="${trimmed,,}"
        case "${trimmed}" in
            ^c|'^\c'|stop|/stop|kill|exit|quit|shutdown|poweroff|halt|end|sigint|sigterm)
                log "Stop command '${line}' received via console. Shutting down..."
                kill -INT "$$" 2>/dev/null || true
                break
                ;;
            *)
                [ -n "${line}" ] && printf '%s\n' "${line}" >&5 2>/dev/null || true
                ;;
        esac
    done
}

start_stop_watcher() {
    # PANEL_STOP_WATCHER=0 keeps panel stdin exclusively for the application
    # (direct-stdin passthrough mode); =1 or auto (default) engages the watcher.
    case "${PANEL_STOP_WATCHER:-auto}" in
        0|false|off|disabled|no) return 1 ;;
    esac
    if [ "${STOP_WATCHER_PID}" -eq 0 ]; then
        # Probe first inside a subshell: a failed exec redirection would exit
        # the launcher itself if fd 0 were closed (bash non-interactive rule).
        if ( exec 9<&0 ) 2>/dev/null; then
            # Dup console stdin to fd 3 in the main shell before backgrounding
            # - spawn-time redirections on background jobs do not survive on
            # some daemon/container runtimes (observed EOF-on-read otherwise).
            exec 3<&0 2>/dev/null || true
            panel_stop_watcher &
            STOP_WATCHER_PID=$!
            # The watcher subshell holds its own dup; close ours so the dup is
            # not inherited by every child the launcher spawns afterwards.
            exec 3>&- 2>/dev/null || true
        fi
    fi
    [ "${STOP_WATCHER_PID}" -gt 1 ] 2>/dev/null && return 0 || return 1
}

# Launch the server as a background child so signals land on the launcher,
# which orchestrates graceful shutdown (console command -> SIGTERM -> SIGKILL).
#
#   mode=watch : universal FIFO plumbing. The launcher owns panel stdin; a
#                background watcher scans it, recognizes stop commands (from
#                Wings daemons AND typed by users) and forwards every other
#                line to the server console FIFO. This fixes Stop on panels
#                that deliver "^C"/"stop" as TEXT (Feather Panel and other
#                Tty:true daemons) without eating regular console commands.
#   mode=proxy : legacy fallback (PANEL_STOP_WATCHER=0) for BungeeCord-family
#                proxies: a translator converts the panel's "stop" to "end".
#   mode=direct: legacy fallback: the server inherits panel stdin directly
#                (same contract as official Pterodactyl yolks).
launch_with_fifo() {
    local cmd="$1"
    local mode="$2"

    if [ "${mode}" = "direct" ]; then
        TRANSLATOR_PID=""
        STOP_WATCHER_PID=0
        # CRITICAL: an async (background) command in a non-job-control shell
        # gets its stdin redirected to /dev/null by POSIX rules. Without the
        # explicit `<&0` the server would never receive the panel's console
        # input ("stop"/"end") and would see instant EOF instead.
        bash -c "exec ${cmd}" <&0 &
        SERVER_PID=$!
    else
        rm -f "${FIFO_PATH}" 2>/dev/null || true
        mkfifo "${FIFO_PATH}" 2>/dev/null || true
        # Hold OUR read-write end open FIRST (`<>` never blocks on open, unlike
        # `>` which waits for a reader and can deadlock). Every later open on
        # this FIFO - translator write end, server read end - then succeeds
        # immediately. Closing fd 5 at shutdown is what terminates the server's
        # stdin reader cleanly.
        exec 5<>"${FIFO_PATH}" 2>/dev/null || true
        if [ "${mode}" = "watch" ]; then
            # Watcher: single reader of panel stdin; forwards console commands
            # to the server FIFO and intercepts stop commands. The watcher
            # inherits fd 5 (the held FIFO end) as its forwarding write end;
            # the launcher keeps fd 5 too for send_stop_command.
            if ! start_stop_watcher; then
                # Watcher unavailable (PANEL_STOP_WATCHER=0 mid-flight, or a
                # closed stdin): fall back to direct-stdin passthrough so the
                # server keeps the official yolk contract.
                bash -c "exec ${cmd}" <&0 &
                SERVER_PID=$!
            else
                ( bash -c "exec ${cmd}" ) < "${FIFO_PATH}" &
                SERVER_PID=$!
            fi
        else
            # Legacy proxy translator: panel stdin -> FIFO (stop -> end).
            # This is the ONLY reader of panel stdin, so console lines are
            # never stolen. If panel stdin EOFs early, it exits silently.
            ( while IFS= read -r line || [ -n "${line}" ]; do
                  [ "${line}" = "stop" ] && line="end"
                  printf '%s\n' "${line}" >&4
              done ) 4>"${FIFO_PATH}" &
            TRANSLATOR_PID=$!
            ( bash -c "exec ${cmd}" ) < "${FIFO_PATH}" &
            SERVER_PID=$!
        fi
    fi

    # Wait for server. Grace-period timers only start counting once a
    # shutdown has been initiated (stop command / signal), never at startup.
    # 10s grace (console stop / signals), then SIGTERM, then force-kill 10s
    # later plus an orphan sweep - the whole sequence finishes inside the
    # ~30s window panels give before they force-kill the container.
    # `sleep 1 &` + wait: the background sleep is killable, so a signal that
    # arrives mid-loop isn't delayed by a blocked foreground sleep.
    local grace_count=0
    local grace_max="${STOP_GRACE_SECONDS:-10}"
    while kill -0 "${SERVER_PID}" 2>/dev/null; do
        sleep 1 &
        local sleep_pid=$!
        wait "${sleep_pid}" 2>/dev/null
        if [ "${SHUTDOWN_INITIATED}" -eq 1 ]; then
            grace_count=$((grace_count + 1))
            if [ "${grace_count}" -eq "${grace_max}" ]; then
                log "Server not responding to stop request after ${grace_max}s, sending SIGTERM..."
                kill -TERM "${SERVER_PID}" 2>/dev/null || true
            fi
            if [ "${grace_count}" -ge $((grace_max + 10)) ]; then
                warn "Server still running, force killing..."
                terminate_process_tree "${SERVER_PID}" 5
                break
            fi
        fi
    done

    # Grace period elapsed: make sure EVERYTHING is gone. A server that
    # ignores both the console stop command and SIGTERM (or leaves detached
    # double-forked children behind) must not survive the stop - otherwise the
    # panel shows "stopping" while the server keeps serving.
    if [ "${SHUTDOWN_INITIATED}" -eq 1 ]; then
        terminate_process_tree "${SERVER_PID}" 3
        sweep_stray_processes graceful
    fi

    wait "${SERVER_PID}" 2>/dev/null
    EXIT_STATUS=$?

    # A server that exited BECAUSE of our stop request (SIGTERM=143 /
    # SIGKILL=137 from the grace timer, or 130=SIGINT) must be reported to
    # the panel as a CLEAN stop. If we reported 143/137 the panel would mark
    # the server as "crashed" on Stop/Restart instead of gracefully offline.
    if [ "${SHUTDOWN_INITIATED}" -eq 1 ]; then
        case "${EXIT_STATUS}" in
            130 | 137 | 143)
                log "Server stopped gracefully (exit ${EXIT_STATUS} after stop request)."
                EXIT_STATUS=0
                ;;
        esac
    fi

    # Tear down stdin helpers and FIFOs
    if [ -n "${TRANSLATOR_PID}" ]; then
        kill "${TRANSLATOR_PID}" 2>/dev/null || true
        wait "${TRANSLATOR_PID}" 2>/dev/null || true
        TRANSLATOR_PID=""
    fi
    if [ -n "${STOP_WATCHER_PID}" ] && [ "${STOP_WATCHER_PID}" -gt 1 ] 2>/dev/null; then
        kill -9 "${STOP_WATCHER_PID}" 2>/dev/null || true
        wait "${STOP_WATCHER_PID}" 2>/dev/null || true
        STOP_WATCHER_PID=0
    fi
    exec 5>&- 2>/dev/null || true
    rm -f "${FIFO_PATH}" 2>/dev/null || true
    return ${EXIT_STATUS}
}

# Launch the server with the right stdin plumbing for the current
# PANEL_STOP_WATCHER setting. The watcher is the default: it guarantees the
# panel Stop button works on every daemon (signals, pipes and TTYs alike)
# while keeping the server console usable.
launch_server() {
    local cmd="$1"
    local want_proxy=0
    case "${TYPE}" in
        bungeecord|waterfall|velocity) want_proxy=1 ;;
    esac
    case "${PANEL_STOP_WATCHER:-auto}" in
        0|false|off|disabled|no)
            if [ "${want_proxy}" = "1" ]; then
                launch_with_fifo "${cmd}" legacy-proxy
            else
                launch_with_fifo "${cmd}" direct
            fi
            ;;
        *)
            launch_with_fifo "${cmd}" watch
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Boot card (resolved runtime values, PLE-style) + orphan pre-start sweep
# ---------------------------------------------------------------------------
print_card_row() {
    # 68-col card: panel consoles are ~70-80 cols; wider cards wrap and render
    # doubled/garbled on narrower panel consoles.
    local label="$1" value="$2" color="$3"
    # Some coreutils/BusyBox builds print partial output to stdout AND fail
    # (e.g. `id -un` for a uid without a passwd entry), which would smuggle a
    # literal newline into the value and split the card row in half. Strip
    # everything after the first line and flatten control whitespace.
    value="${value%%[$'\r\n']*}"
    value="${value//$'\t'/ }"
    if [ "${#value}" -gt 42 ]; then
        value="${value:0:39}..."
    fi
    printf " ${C_DIM}│${C_RESET}  ${C_LIME}◆${C_RESET} ${C_BOLD}%-15s${C_RESET} : ${color}%-42s${C_RESET} ${C_DIM}│${C_RESET}\n" "${label}" "${value}"
}

print_boot_card() {
    local java_disp="Native / Non-Java runtime"
    if command -v java >/dev/null 2>&1; then
        java_disp="$(java -version 2>&1 | head -n1 | sed 's/^openjdk version /OpenJDK /; s/^openjdk /Java /' | tr -d '"')"
        [ -n "${JAVA_HOME:-}" ] && java_disp="${java_disp} (${JAVA_HOME})"
    fi
    # Memory tuning: Xmx the panel allocated, plus the cgroup hard limit when
    # the kernel exposes one, plus the classic 85%-safe-heap guidance.
    local mem_mb="${SERVER_MEMORY:-1024}" mem_line
    case "${mem_mb}" in *[!0-9]* | "") mem_mb=1024 ;; esac
    mem_line="${mem_mb}MB Xmx (safe heap $((mem_mb * 85 / 100))MB)"
    if [ -f /sys/fs/cgroup/memory.max ]; then
        local _cgmax
        _cgmax=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
        if [ "${_cgmax}" != "max" ] && [ -n "${_cgmax}" ] && [ "${_cgmax}" -gt 0 ] 2>/dev/null; then
            mem_line="${mem_mb}MB Xmx (cgroup limit $((_cgmax / 1024 / 1024))MB)"
        fi
    fi
    # Entry point: what will actually be executed after this card.
    local entry_point
    case "${TYPE}" in
        bedrock)    entry_point="./bedrock_server" ;;
        pocketmine) entry_point="php ./PocketMine-MP.phar" ;;
        custom)     entry_point="${CUSTOM_COMMAND:-java -Xmx${mem_mb}M -jar ${SERVER_JARFILE:-server.jar}}" ;;
        *)
            if [ -f unix_args.txt ] && { [ "${TYPE}" = "forge" ] || [ "${TYPE}" = "neoforge" ]; }; then
                entry_point="java @unix_args.txt nogui"
            else
                entry_point="java -jar ${SERVER_JARFILE:-server.jar}"
            fi
            ;;
    esac
    local disk_free
    disk_free="$(df -h . 2>/dev/null | awk 'NR==2 {print $4}')"
    [ -n "${disk_free}" ] || disk_free="unknown"

    printf " ${C_DIM}┌──────────────────────────────────────────────────────────────────┐${C_RESET}\n"
    print_card_row "Server Type" "${TYPE}" "${C_GREEN}"
    print_card_row "MC Version" "${MINECRAFT_VERSION:-latest}$([ "${BUILD_NUMBER:-latest}" != "latest" ] && echo " build ${BUILD_NUMBER}")" "${C_GREEN}"
    print_card_row "Java Runtime" "${java_disp}" "${C_GREEN}"
    print_card_row "Entry Point" "${entry_point}" "${C_YELLOW}"
    print_card_row "Target Jarfile" "${SERVER_JARFILE:-n/a (proxy/bedrock/php)}" "${C_YELLOW}"
    print_card_row "GC Tuning" "${FLAGS_SOURCE:-JAVA_FLAGS}" "${C_CYAN}"
    print_card_row "Memory Tuning" "${mem_line}" "${C_MAGENTA}"
    print_card_row "Disk Free" "${disk_free} available" "${C_MAGENTA}"
    print_card_row "Port Allocation" "${SERVER_PORT:-25565} (${SERVER_IP:-0.0.0.0})" "${C_GREEN}"
    if [ "${TYPE}" = "github" ]; then
        print_card_row "GitHub Source" "${GITHUB_REPO:-not-set} @ ${GITHUB_TAG:-latest}" "${C_MAGENTA}"
    fi
    print_card_row "Host Platform" "${PANEL_TYPE:-Docker / Standalone}" "${C_BLUE}"
    print_card_row "Server UUID" "${P_SERVER_UUID:-${SERVER_UUID:-not-provided}}" "${C_DIM}"
    print_card_row "Egg Self-Update" "$([ "${AUTO_UPDATE_EGG:-1}" = "1" ] && echo Enabled || echo Disabled)" "${C_GREEN}"
    print_card_row "Reinstall Mode" "$([ "${AUTO_UPDATE:-1}" = "1" ] && echo "Always update on reinstall" || echo "Keep files on reinstall")" "${C_GREEN}"
    print_card_row "Stop Watcher" "$([ "${PANEL_STOP_WATCHER:-auto}" = "0" ] && echo Disabled || echo Enabled)" "${C_CYAN}"
    local _card_user _card_uid
    _card_user="$(id -un 2>/dev/null || true)"
    _card_uid="$(id -u 2>/dev/null || true)"
    # BusyBox-style `id -un` can print the numeric uid to stdout AND exit 1;
    # take the first line only and fall back to '?' when empty.
    _card_user="${_card_user%%[$'\r\n']*}"
    [ -n "${_card_user}" ] || _card_user="?"
    [ -n "${_card_uid}" ] || _card_uid="?"
    print_card_row "Process User" "${_card_user} (uid ${_card_uid})" "${C_BLUE}"
    local _card_arch _card_kernel
    _card_arch="$(uname -m 2>/dev/null || true)"
    _card_kernel="$(uname -s 2>/dev/null || true)"
    [ -n "${_card_arch}" ] || _card_arch="unknown"
    [ -n "${_card_kernel}" ] || _card_kernel="Linux"
    print_card_row "Architecture" "${_card_arch} (${_card_kernel})" "${C_CYAN}"
    print_card_row "Working Dir" "${SERVER_DIR}" "${C_DIM}"
    printf " ${C_DIM}└──────────────────────────────────────────────────────────────────┘${C_RESET}\n\n"
}

# ---------------------------------------------------------------------------
# Non-Java server types
# ---------------------------------------------------------------------------
case "${TYPE}" in
    bedrock)
        [ ! -f ./bedrock_server ] && { error "bedrock_server executable not found in $(pwd)"; sleep 3; exit 1; }
        chmod +x ./bedrock_server 2>/dev/null || true
        phase "Server Launch"
        print_boot_card
        sweep_stray_processes quick
        log "Executing: ./bedrock_server (LD_LIBRARY_PATH=.)"
        printf "%b>>> ./bedrock_server%b\n\n" "${C_GREEN}${C_BOLD}" "${C_RESET}"
        launch_server "env LD_LIBRARY_PATH=. ./bedrock_server"
        EXIT_STATUS=$?
        if [ ${EXIT_STATUS} -ne 0 ] && [ ${EXIT_STATUS} -ne 130 ] && [ ${EXIT_STATUS} -ne 143 ]; then
            _egg_error_log "launcher" "=== CRASH: exit=${EXIT_STATUS} type=${TYPE} ==="
            print_crash_diagnostics "${EXIT_STATUS}" 2>/dev/null || true
        else
            _egg_error_log "launcher" "=== server process exited cleanly (code ${EXIT_STATUS}) ==="
        fi
        exit ${EXIT_STATUS}
        ;;
    pocketmine)
        [ ! -f ./PocketMine-MP.phar ] && { error "PocketMine-MP.phar not found in $(pwd)"; sleep 3; exit 1; }
        phase "Server Launch"
        print_boot_card
        sweep_stray_processes quick
        log "Executing: php PocketMine-MP.phar"
        printf "%b>>> php ./PocketMine-MP.phar --no-wizard%b\n\n" "${C_GREEN}${C_BOLD}" "${C_RESET}"
        launch_server "php ./PocketMine-MP.phar --no-wizard"
        EXIT_STATUS=$?
        if [ ${EXIT_STATUS} -ne 0 ] && [ ${EXIT_STATUS} -ne 130 ] && [ ${EXIT_STATUS} -ne 143 ]; then
            _egg_error_log "launcher" "=== CRASH: exit=${EXIT_STATUS} type=${TYPE} ==="
            print_crash_diagnostics "${EXIT_STATUS}" 2>/dev/null || true
        else
            _egg_error_log "launcher" "=== server process exited cleanly (code ${EXIT_STATUS}) ==="
        fi
        exit ${EXIT_STATUS}
        ;;
    custom)
        if [ -n "${CUSTOM_COMMAND:-}" ]; then
            phase "Server Launch"
            print_boot_card
            sweep_stray_processes quick
            log "Executing custom command: ${CUSTOM_COMMAND}"
            printf "%b>>> %s%b\n\n" "${C_GREEN}${C_BOLD}" "${CUSTOM_COMMAND}" "${C_RESET}"
            launch_server "${CUSTOM_COMMAND}"
            EXIT_STATUS=$?
            if [ ${EXIT_STATUS} -ne 0 ] && [ ${EXIT_STATUS} -ne 130 ] && [ ${EXIT_STATUS} -ne 143 ]; then
                _egg_error_log "launcher" "=== CRASH: exit=${EXIT_STATUS} type=${TYPE} ==="
                print_crash_diagnostics "${EXIT_STATUS}" 2>/dev/null || true
            else
                _egg_error_log "launcher" "=== server process exited cleanly (code ${EXIT_STATUS}) ==="
            fi
            exit ${EXIT_STATUS}
        fi
        ;;
esac

# Everything below is a Java server.
# GC tuning: an explicit JAVA_FLAGS value (the egg default is Aikar's tuned
# G1GC set) always wins. When JAVA_FLAGS is empty, GC_TYPE picks the tuning:
# 'auto' = Aikar G1GC, 'zgc' = ZGC (great for 8GB+ allocations on Java 21+),
# 'parallel' = ParallelGC.
GC_TYPE=$(echo "${GC_TYPE:-auto}" | tr '[:upper:]' '[:lower:]')
FLAGS_SOURCE="JAVA_FLAGS"
if [ -z "${JAVA_FLAGS:-}" ]; then
    FLAGS_SOURCE="GC_TYPE=${GC_TYPE}"
    case "${GC_TYPE}" in
        zgc)
            JAVA_FLAGS="-XX:+UseZGC -XX:+ZGenerational -XX:+ParallelRefProcEnabled -XX:-OmitStackTraceInFastThrow"
            ;;
        parallel)
            JAVA_FLAGS="-XX:+UseParallelGC -XX:+ParallelRefProcEnabled -XX:+DisableExplicitGC"
            ;;
        *)
            JAVA_FLAGS="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1"
            ;;
    esac
fi
EXTRA_ARGS="${EXTRA_ARGS:-}"

# Modern Forge / NeoForge servers launch through a generated unix_args.txt.
if [ -f unix_args.txt ] && { [ "${TYPE}" = "forge" ] || [ "${TYPE}" = "neoforge" ]; }; then
    JAVA_CMD="java -Xms128M -Xmx${MEMORY}M ${JAVA_FLAGS} @unix_args.txt nogui ${EXTRA_ARGS}"
else
    if [ ! -f "${SERVER_JARFILE:-server.jar}" ]; then
        cand_jar=$(ls *.jar 2>/dev/null | grep -v 'installer' | head -n1)
        if [ -n "${cand_jar}" ]; then
            warn "Configured jar '${SERVER_JARFILE:-server.jar}' not found, but found '${cand_jar}'. Launching with '${cand_jar}'."
            SERVER_JARFILE="${cand_jar}"
        else
            error "Server jar file '${SERVER_JARFILE:-server.jar}' was not found in $(pwd)!"
            error "Please check server settings or trigger Reinstall Server in your panel."
            sleep 3
            exit 1
        fi
    fi
    JAVA_CMD="java -Xms128M -Xmx${MEMORY}M ${JAVA_FLAGS} -jar ${SERVER_JARFILE:-server.jar} ${EXTRA_ARGS}"
fi

phase "Server Launch"
print_boot_card
sweep_stray_processes quick
log "Executing: ${JAVA_CMD}"
log "JVM flags source: ${FLAGS_SOURCE}"
printf "%b>>> %s%b\n\n" "${C_GREEN}${C_BOLD}" "${JAVA_CMD}" "${C_RESET}"

launch_server "${JAVA_CMD}"
EXIT_STATUS=$?

if [ ${EXIT_STATUS} -ne 0 ] && [ ${EXIT_STATUS} -ne 130 ] && [ ${EXIT_STATUS} -ne 143 ]; then
    _egg_error_log "launcher" "=== CRASH: exit=${EXIT_STATUS} type=${TYPE} mc=${MINECRAFT_VERSION:-latest} ==="
    _egg_error_log "launcher" "java=$(java -version 2>&1 | head -n1) | flags_source=${FLAGS_SOURCE:-JAVA_FLAGS} mem=${SERVER_MEMORY:-1024}"
    _egg_error_log "launcher" "command=${JAVA_CMD}"
    [ -f eula.txt ] && _egg_error_log "launcher" "eula: $(grep -i '^eula' eula.txt 2>/dev/null | head -n1)"
    if [ -f logs/latest.log ]; then
        _egg_error_log "launcher" "--- last errors from logs/latest.log ---"
        grep -iE '(error|exception|fatal|failed)' logs/latest.log 2>/dev/null | tail -n20 >> "${ERROR_LOG}" 2>/dev/null || true
    fi
    print_crash_diagnostics "${EXIT_STATUS}"
    _egg_error_log "launcher" "--- end crash diagnostics ---"
else
    _egg_error_log "launcher" "=== server process exited cleanly (code ${EXIT_STATUS}) ==="
fi

exit ${EXIT_STATUS}
