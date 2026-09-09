#!/bin/bash
# =============================================================================
#  Multi-Language Eggs - Multi-Language Launcher
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Prog-Language-Eggs)
#
#  Multi-Panel Compatibility:
#    - Pterodactyl Panel (Wings)
#    - Pelican Panel
#    - Feather Panel (feather-panel / renoki-co)
#    - PufferPanel
#    - Jexactyl / Wisp
#    - Standalone Docker & Kubernetes
# =============================================================================

# --- Visual theme -------------------------------------------------------------
# Default: Prog-Language Eggs agent theme (agent-style console output).
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

# --- Troubleshooting infrastructure ---------------------------------------------
# phase(): clean dim section headers so boot logs are scannable top-to-bottom.
# _egg_error_log(): central append-only error journal (egg-level failures only)
# at .logs/launcher-errors.log - shared with the entrypoint, survives panel
# scrollback loss. Call sites: git failures, runtime installs, dependency
# installs, health checks, crashes.
phase() { printf "\n%b── %s %b\n" "${C_DIM}" "$*" "────────────────────────${C_RESET}"; }

ERROR_LOG=""
_egg_error_log() {
    if [ -z "${ERROR_LOG}" ]; then
        local d="${WORK_DIR:-${PWD}}/.logs"
        if mkdir -p "${d}" 2>/dev/null && [ -w "${d}" ]; then
            ERROR_LOG="${d}/launcher-errors.log"
        else
            ERROR_LOG="/tmp/potenfyr-errors.log"
        fi
    fi
    printf '[%s] [%s] [panel=%s] %s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date)" \
        "${1:-launcher}" "${PANEL_TYPE:-unknown}" "${2:-unknown error}" \
        >> "${ERROR_LOG}" 2>/dev/null || true
}

if [ "${CLI_THEME}" = "classic" ]; then
    log()   { printf "%b %b\n" "${C_CYAN}${C_BOLD}[PotenFYR]${C_RESET}" "$*"; }
    ok()    { printf "%b %b\n" "${C_GREEN}${C_BOLD}[PotenFYR][✓]${C_RESET}" "$*"; }
    warn()  { printf "%b %b\n" "${C_YELLOW}${C_BOLD}[PotenFYR][!]${C_RESET}" "${C_YELLOW}$*${C_RESET}"; }
    fail()  { printf "%b %b\n" "${C_RED}${C_BOLD}[PotenFYR][✗]${C_RESET}" "${C_RED}$*${C_RESET}"; _egg_error_log "launcher" "$*"; exit 1; }
    info()  { printf "%b %b\n" "${C_BLUE}${C_BOLD}[PotenFYR][i]${C_RESET}" "$*"; }
else
    log()   { printf "%b %b\n" "${C_LIME}${C_BOLD}</> prog-language-eggs${C_RESET}${C_DIM} ▸${C_RESET}" "$*"; }
    ok()    { printf "%b %b\n" "${C_LIME}${C_BOLD}</> prog-language-eggs ✔${C_RESET}" "${C_GREEN}$*${C_RESET}"; }
    warn()  { printf "%b %b\n" "${C_GOLD}${C_BOLD}</> prog-language-eggs ⚠${C_RESET}" "${C_YELLOW}$*${C_RESET}"; }
    fail()  { printf "%b %b\n" "${C_RED}${C_BOLD}</> prog-language-eggs ✖${C_RESET}" "${C_RED}$*${C_RESET}"; _egg_error_log "launcher" "$*"; exit 1; }
    info()  { printf "%b %b\n" "${C_CYAN}${C_BOLD}</> prog-language-eggs ℹ${C_RESET}" "$*"; }
fi

# --- Security baseline ----------------------------------------------------------
# No world-writable files from the launcher; no core dumps eating disk space.
umask 022
ulimit -c 0 2>/dev/null || true

# --- Process Lifecycle Management & Signal Handling ---
RUN_LOOP=1
CHILD_PID=0
HEALTH_PID=""
PROC_PIDS=""
SLEEP_PID=0
POST_RUN_COMMAND="${POST_RUN_COMMAND:-}"

# Recursively discover all child and descendant PIDs of a process
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

# Container-wide sweep for orphaned processes (pm2 god daemons, detached
# workers, double-forked helpers, background spawners) that escaped every
# tracked process tree - they keep serving even after the main app dies.
#   sweep_stray_processes graceful -> TERM, wait, escalate to KILL (panel stop)
#   sweep_stray_processes quick    -> immediate SIGKILL (pre-start port cleanup)
# Excludes: the main shell, console-mirror helpers, and the stdin watcher.
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
        log "Swept ${_killed} stray process(es) (pm2 daemons / detached workers)."
        _egg_error_log "launcher" "swept ${_killed} stray process(es) during ${mode} sweep" >/dev/null 2>&1 || true
    fi
    return 0
}

# Gracefully terminate a process and its full process tree, escalating to SIGKILL
terminate_process_tree() {
    local root_pid="$1"
    local timeout="${2:-5}"
    [ -z "${root_pid}" ] || [ "${root_pid}" -le 1 ] 2>/dev/null && return 0
    kill -0 "${root_pid}" 2>/dev/null || return 0

    local pids
    pids="$(get_all_child_pids "${root_pid}") ${root_pid}"

    # Step 1: Send SIGTERM and SIGINT for graceful stop across entire tree
    for p in ${pids}; do
        kill -TERM "${p}" 2>/dev/null || true
        kill -INT "${p}" 2>/dev/null || true
    done

    # Step 2: Poll every 0.2s for graceful exit
    local waited=0
    local max_wait=$((timeout * 5))
    while kill -0 "${root_pid}" 2>/dev/null && [ "${waited}" -lt "${max_wait}" ]; do
        sleep 0.2
        waited=$((waited + 1))
    done

    # Step 3: Escalate to SIGKILL if any process in the tree remains alive
    if kill -0 "${root_pid}" 2>/dev/null; then
        pids="$(get_all_child_pids "${root_pid}") ${root_pid}"
        for p in ${pids}; do
            kill -KILL "${p}" 2>/dev/null || true
            kill -9 "${p}" 2>/dev/null || true
        done
        sleep 0.3
    fi

    # Step 4: Reap child
    wait "${root_pid}" 2>/dev/null || true
}

handle_signal() {
    # Ignore further signals during shutdown to prevent recursion
    trap '' SIGTERM SIGINT SIGHUP SIGQUIT
    RUN_LOOP=0
    log "Received shutdown signal. Stopping application process(es)..."

    # Stop restart sleep if active
    if [ "${SLEEP_PID}" -gt 1 ] 2>/dev/null; then
        kill -9 "${SLEEP_PID}" 2>/dev/null || true
        SLEEP_PID=0
    fi

    # Stop the stdin stop-command watcher
    if [ "${STOP_WATCHER_PID}" -gt 1 ] 2>/dev/null; then
        kill -9 "${STOP_WATCHER_PID}" 2>/dev/null || true
        STOP_WATCHER_PID=0
    fi

    # Stop Health check probe if active
    if [ -n "${HEALTH_PID:-}" ] && [ "${HEALTH_PID}" -gt 1 ] 2>/dev/null; then
        terminate_process_tree "${HEALTH_PID}" 1
        HEALTH_PID=""
    fi

    # Stop Procfile supervisor children if active
    if [ -n "${PROC_PIDS:-}" ]; then
        for p in ${PROC_PIDS}; do
            [ -n "${p}" ] && [ "${p}" -gt 1 ] 2>/dev/null && terminate_process_tree "${p}" 2
        done
        PROC_PIDS=""
    fi

    # Stop main child process tree if active.
    # Panels/Wings escalate to SIGKILL ~10s after the stop request (Pelican and
    # current Pterodactyl Wings), so the whole graceful shutdown below must stay
    # inside that window: health 1s + procfile 2s + main child 5s + sweep 2s.
    if [ -n "${CHILD_PID:-}" ] && [ "${CHILD_PID}" -gt 1 ] 2>/dev/null; then
        terminate_process_tree "${CHILD_PID}" 5
        CHILD_PID=0
    fi

    # Container-wide sweep: catch orphaned/double-forked processes that escaped
    # the child tree (re-parented to PID 1 or detached from any tracked pid).
    # Without this, such strays keep serving after the panel shows "stopping".
    sweep_stray_processes graceful

    if [ -n "${POST_RUN_COMMAND:-}" ]; then
        log "Executing POST_RUN_COMMAND: ${POST_RUN_COMMAND}..."
        eval "${POST_RUN_COMMAND}" || true
    fi

    ok "Application process stopped cleanly"
    exit 0
}

trap handle_signal SIGTERM SIGINT SIGHUP SIGQUIT

# --- Panel Stop Command Watcher (stdin) ---------------------------------------
# Wings-family daemons (Feather Panel, Pterodactyl, Pelican, Jexactyl, Wisp)
# create server containers with Tty:true and deliver the configured stop
# command ("^C" etc.) as console TEXT on that TTY stdin instead of raising a
# signal. The literal text "^C" is not a real INTR byte, so the kernel never
# generates SIGINT, and without a reader the stop line just sits in the tty
# input buffer while the panel hangs on "stopping" until the daemon times out
# and force-kills the container. This watcher scans console input (pipe OR
# tty) and raises our own shutdown trap when a stop command is seen. It starts
# after the interactive setup wizard so first-boot prompts still own stdin,
# and only consumes lines that match a stop command.
# PANEL_STOP_WATCHER=0 disables the watcher entirely; =1 forces it on.
STOP_WATCHER_PID=0

panel_stop_watcher() {
    local line trimmed
    # Reads fd 3, a dup of the console stdin taken in the main shell below, so
    # the watcher never races the main shell or the app for fd 0 itself.
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
        esac
    done
    exec 3>&- 2>/dev/null || true
}

start_stop_watcher() {
    # Panels (Tty:true containers) deliver the stop command as text on stdin,
    # so the watcher must engage on TTYs as well as pipes. Set
    # PANEL_STOP_WATCHER=0 to keep stdin exclusively for the application.
    case "${PANEL_STOP_WATCHER:-auto}" in
        0|false|off|disabled|no) return 0 ;;
    esac
    if [ "${STOP_WATCHER_PID}" -eq 0 ]; then
        # Probe first inside a subshell: a failed exec redirection would exit
        # the launcher itself if fd 0 were closed (bash non-interactive rule).
        if ( exec 3<&0 ) 2>/dev/null; then
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
}

# Determine active working directory across panels
WORK_DIR="${WORK_DIR:-${PWD}}"
if [ ! -d "${WORK_DIR}" ]; then
    if [ -d "/home/container" ]; then
        WORK_DIR="/home/container"
    elif [ -d "/server" ]; then
        WORK_DIR="/server"
    elif [ -d "/app" ]; then
        WORK_DIR="/app"
    else
        WORK_DIR="${PWD}"
    fi
fi

cd "${WORK_DIR}" 2>/dev/null || true

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:${PATH}"
export PATH="${WORK_DIR}/.runtimes/bin:${WORK_DIR}/.local/bin:${WORK_DIR}/bin:${WORK_DIR}/node_modules/.bin:${WORK_DIR}/custom/bin:${PATH}"
export PATH="/opt/runtimes/bin:/opt/runtimes/bun/bin:/opt/runtimes/deno/bin:/opt/runtimes/python/bin:/opt/runtimes/zig:/opt/runtimes/dart-sdk/bin:/opt/runtimes/nim/bin:/opt/runtimes/gleam/bin:/opt/runtimes/odin:/opt/runtimes/custom:/opt/runtimes/custom/bin:${PATH}"
export PATH="/root/.cargo/bin:/opt/cargo/bin:${WORK_DIR}/.cargo/bin:${PATH}"
export PATH="/opt/go/bin:${WORK_DIR}/go/bin:${PATH}"
export PATH="/opt/dotnet:${WORK_DIR}/.dotnet:${PATH}"

CONF_FILE="${WORK_DIR}/.multi-prog.conf"

save_conf() {
    local key="$1" val="$2"
    grep -v "^${key}=" "${CONF_FILE}" 2>/dev/null > "${CONF_FILE}.tmp" || true
    printf '%s=%s\n' "${key}" "${val}" >> "${CONF_FILE}.tmp"
    mv "${CONF_FILE}.tmp" "${CONF_FILE}"
    chmod 600 "${CONF_FILE}" 2>/dev/null || true
}

# --- Security helpers --------------------------------------------------------
# redact_url: never echo credentials embedded in URLs to console/logs.
redact_url() {
    local u="$1"
    u=$(printf '%s' "${u}" | sed -E 's#//[^/@[:space:]]+:[^/@[:space:]]+@#//***:***@#g')
    [ -n "${GIT_AUTH_TOKEN:-}" ] && u=$(printf '%s' "${u}" | sed -e "s#${GIT_AUTH_TOKEN}#***#g")
    printf '%s' "${u}"
}
# valid_http_url: strict scheme/host allowlist; blocks header injection & junk.
valid_http_url() {
    local u="$1"
    local re='^https?://[A-Za-z0-9._-]+(:[0-9]+)?(/[A-Za-z0-9._~:/?%#@!$&()*+,;=-]*)?$'
    [[ "$u" =~ $re ]]
}
# valid_git_url: https / ssh / git@ forms only.
valid_git_url() {
    local u="$1"
    local re_https='^https://[A-Za-z0-9._~-]+(:[0-9]+)?(/[A-Za-z0-9._~:/?%#@!$&()*+,;=-]*)?$'
    local re_ssh='^(ssh://)?[A-Za-z0-9._~-]+@[A-Za-z0-9.-]+[:/][A-Za-z0-9._/~%-]+\.git$|^(ssh://)?[A-Za-z0-9._~-]+@[A-Za-z0-9.-]+[:/][A-Za-z0-9._/-]+$'
    [[ "$u" =~ $re_https ]] && return 0
    [[ "$u" =~ $re_ssh ]]
}

# -----------------------------------------------------------------------------
# sync_git_repo: converge the workspace onto the latest commit of GIT_BRANCH.
#   * Inputs are trimmed - panel startup forms often add stray spaces/newlines
#     to GIT_REPO / GIT_AUTH_TOKEN / GIT_BRANCH, which silently broke clones.
#   * Fetch/reset errors are shown (token-redacted) instead of being swallowed.
#   * reset --hard FETCH_HEAD (not origin/<branch>): shallow single-branch
#     clones and branch switches leave the origin/<branch> ref stale/missing,
#     which permanently pinned servers to the first cloned commit.
#   * origin is re-pointed at the CURRENT GIT_REPO/token every boot so repo or
#     credential edits in the Startup tab take effect on the next restart.
#   * Before any overwrite the existing codebase is archived to
#     .logs/code-archives/ (5 newest kept) so a bad sync can be rolled back.
#   * A workspace that already holds files (no .git) gets the repository
#     fetched OVER it instead of failing the clone ("directory not empty").
# -----------------------------------------------------------------------------
_git_ws_has_files() {
    find . -mindepth 1 -maxdepth 1 \
        -not -name '.git' -not -name '.logs' -not -name '.potenfyr' \
        -not -name '.multi-prog.conf' -not -name '.runtimes' \
        -not -name '.npm' -not -name '.cache' -not -name '.environments' \
        2>/dev/null | grep -q .
}

_git_archive_workspace() {
    # Safety-net snapshot; never fatal (a failed backup must not block the boot).
    local arch_dir="${WORK_DIR}/.logs/code-archives"
    local stamp arch _old
    mkdir -p "${arch_dir}" 2>/dev/null || return 0
    stamp="$(date +%Y%m%d-%H%M%S)"
    arch="${arch_dir}/codebase-${stamp}.tar.gz"
    tar -czf "${arch}" \
        --exclude='./.git' --exclude='./.logs' --exclude='./.runtimes' \
        --exclude='./.npm' --exclude='./.cache' --exclude='./.environments' \
        --exclude='./.potenfyr' --exclude='./.multi-prog.conf' \
        --exclude='./node_modules' \
        -C "${WORK_DIR}" . 2>/dev/null || { rm -f "${arch}"; return 0; }
    # Keep only the 5 newest archives.
    ls -1t "${arch_dir}"/codebase-*.tar.gz 2>/dev/null | tail -n +6 \
        | while IFS= read -r _old; do rm -f "${_old}" 2>/dev/null || true; done
    info "Codebase archived before git sync: .logs/code-archives/$(basename "${arch}")"
}

_git_redact_err() {
    # git error text can embed the credentialed URL; redact before printing.
    redact_url "$(tr '\n' ' ' < "$1" 2>/dev/null | cut -c1-300)"
}

sync_git_repo() {
    GIT_REPO="$(printf '%s' "${GIT_REPO:-}" | tr -d ' \t\r\n')"
    GIT_BRANCH="$(printf '%s' "${GIT_BRANCH:-main}" | tr -d ' \t\r\n')"
    [ -n "${GIT_BRANCH}" ] || GIT_BRANCH="main"
    GIT_AUTH_TOKEN="$(printf '%s' "${GIT_AUTH_TOKEN:-}" | tr -d ' \t\r\n')"
    # Never let git block the boot on an interactive credential prompt.
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=/bin/true

    local _err _old_head _new_head _new_date _new_subj
    _err="$(mktemp 2>/dev/null || echo "/tmp/potenfyr-git-$$")"

    AUTH_REPO_URL="${GIT_REPO}"
    if [ -n "${GIT_AUTH_TOKEN}" ] && [[ "${GIT_REPO}" =~ ^https:// ]]; then
        AUTH_REPO_URL="https://${GIT_AUTH_TOKEN}@${GIT_REPO#https://}"
    fi

    if [ ! -d ".git" ]; then
        if _git_ws_has_files; then
            _git_archive_workspace
            log "Workspace has existing files - fetching '${GIT_BRANCH}' over them (no wipe)..."
            git init -q . 2>/dev/null || true
            git remote remove origin 2>/dev/null || true
            if git remote add origin "${AUTH_REPO_URL}" 2>"${_err}" \
                    && git fetch --depth 1 origin "${GIT_BRANCH}" 2>"${_err}"; then
                if git reset --hard FETCH_HEAD 2>"${_err}"; then
                    _new_head="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
                    _new_subj="$(git log -1 --format=%s 2>/dev/null || true)"
                    ok "Repository fetched over existing files (commit ${_new_head}: ${_new_subj:-n/a})"
                else
                    warn "Could not apply fetched commits: $(_git_redact_err "${_err}")"
                    _egg_error_log "launcher" "git reset failed on fresh overlay (repo: $(redact_url "${GIT_REPO}"), branch ${GIT_BRANCH})"
                fi
            else
                warn "Git fetch failed - your files were kept unchanged: $(_git_redact_err "${_err}")"
                _egg_error_log "launcher" "git fetch failed on fresh overlay (repo: $(redact_url "${GIT_REPO}"), branch ${GIT_BRANCH}) - check URL, branch name and credentials"
            fi
        else
            log "Cloning repository: $(redact_url "${GIT_REPO}") (branch: ${GIT_BRANCH})..."
            if git clone --branch "${GIT_BRANCH}" --depth 1 "${AUTH_REPO_URL}" . 2>"${_err}"; then
                ok "Repository successfully cloned (commit $(git rev-parse --short HEAD 2>/dev/null || echo '?'))"
            else
                warn "Git clone of branch '${GIT_BRANCH}' failed: $(_git_redact_err "${_err}")"
                _egg_error_log "launcher" "git clone failed on branch ${GIT_BRANCH} (repo: $(redact_url "${GIT_REPO}")) - check URL, branch name and credentials"
                warn "Retrying with the repository's default branch..."
                if git clone --depth 1 "${AUTH_REPO_URL}" . 2>"${_err}"; then
                    ok "Repository cloned (default branch)"
                else
                    warn "Could not clone repository. Check network, URL and credentials, then restart."
                    _egg_error_log "launcher" "git clone failed entirely (repo: $(redact_url "${GIT_REPO}")) - verify URL, credentials (GIT_AUTH_TOKEN) and network egress"
                fi
            fi
        fi
    else
        log "Existing Git repository found - checking for new commits..."
        # Re-point origin at the currently configured repo/token first: either
        # may have been edited in the Startup tab since the first clone.
        git remote set-url origin "${AUTH_REPO_URL}" 2>/dev/null \
            || git remote add origin "${AUTH_REPO_URL}" 2>/dev/null || true
        _old_head="$(git rev-parse --short HEAD 2>/dev/null || echo 'none')"
        if git fetch --depth 1 origin "${GIT_BRANCH}" 2>"${_err}"; then
            _git_archive_workspace
            if git reset --hard FETCH_HEAD 2>"${_err}"; then
                _new_head="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
                _new_date="$(git log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M %Z' 2>/dev/null || true)"
                _new_subj="$(git log -1 --format=%s 2>/dev/null || true)"
                if [ "${_old_head}" != "${_new_head}" ]; then
                    ok "Git updated: ${_old_head} -> ${_new_head} (branch ${GIT_BRANCH}, commit from ${_new_date:-unknown date})"
                    info "Latest commit: ${_new_subj:-n/a}"
                else
                    ok "Already at latest commit ${_new_head} on '${GIT_BRANCH}' (from ${_new_date:-unknown date})"
                fi
            else
                warn "Could not apply fetched commits - code left unchanged: $(_git_redact_err "${_err}")"
                _egg_error_log "launcher" "git reset --hard FETCH_HEAD failed (repo: $(redact_url "${GIT_REPO}"), branch ${GIT_BRANCH}) - restore from .logs/code-archives/ if needed"
            fi
        else
            warn "Git fetch failed - keeping installed code: $(_git_redact_err "${_err}")"
            _egg_error_log "launcher" "git fetch failed (repo: $(redact_url "${GIT_REPO}"), branch ${GIT_BRANCH}) - check URL, branch name and credentials"
        fi
    fi
    rm -f "${_err}" 2>/dev/null || true
}

# --- Variables with defaults ---
LANGUAGE="${LANGUAGE:-auto}"
RUNNER="${RUNNER:-auto}"
MAIN_FILE="${MAIN_FILE:-auto}"
PACKAGE_MANAGER="${PACKAGE_MANAGER:-auto}"
BUILD_COMMAND="${BUILD_COMMAND:-}"
CUSTOM_COMMAND="${CUSTOM_COMMAND:-}"
CUSTOM_INSTALL_COMMAND="${CUSTOM_INSTALL_COMMAND:-}"
CUSTOM_RUNTIME_URL="${CUSTOM_RUNTIME_URL:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-1}"
AUTO_RESTART="${AUTO_RESTART:-0}"
RESTART_DELAY="${RESTART_DELAY:-3}"
DEV_MODE="${DEV_MODE:-0}"
PRE_RUN_COMMAND="${PRE_RUN_COMMAND:-}"
POST_RUN_COMMAND="${POST_RUN_COMMAND:-}"
CLEAN_BUILD_CACHE="${CLEAN_BUILD_CACHE:-1}"
GIT_REPO="${GIT_REPO:-}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_AUTH_TOKEN="${GIT_AUTH_TOKEN:-}"
STARTER_TEMPLATE="${STARTER_TEMPLATE:-}"
SERVER_PORT="${SERVER_PORT:-${PORT:-${FEATHER_PORT:-${PUFFER_PORT:-8080}}}}"
NODE_GYP_SUPPORT="${NODE_GYP_SUPPORT:-1}"
EXTRA_RUNTIMES="${EXTRA_RUNTIMES:-}"
SKIP_RUNTIMES="${SKIP_RUNTIMES:-}"
SKIP_PYTHON="${SKIP_PYTHON:-0}"
DEBUG="${DEBUG:-0}"

# LANGUAGE_VERSION (DB_VERSION-style alias used by some panels/eggs) falls back
# to RUNTIME_VERSION when set; RUNTIME_VERSION stays the canonical variable.
if [ -n "${LANGUAGE_VERSION:-}" ]; then
    RUNTIME_VERSION="${RUNTIME_VERSION:-${LANGUAGE_VERSION}}"
    export RUNTIME_VERSION
fi

[ "${DEBUG}" = "1" ] && set -x
# Route the verbose trace to a log file instead of spamming the panel console
if [ "${DEBUG}" = "1" ] && [ -z "${_POTENFYR_TRACE_FD:-}" ]; then
    mkdir -p "${WORK_DIR}/.logs" 2>/dev/null || true
    if exec 9>>"${WORK_DIR}/.logs/launcher-trace.log" 2>/dev/null; then
        PS4='+ $(date "+%H:%M:%S") ${BASH_SOURCE}:${LINENO}: '
        BASH_XTRACEFD=9
        _POTENFYR_TRACE_FD=1
        log "DEBUG=1 trace -> ${WORK_DIR}/.logs/launcher-trace.log"
    fi
fi

# -----------------------------------------------------------------------------
# 1. Egg Self-Update Engine (EGG_UPDATE_URL)
# -----------------------------------------------------------------------------
# The container entrypoint runs this check too; it is duplicated here so
# panels/hosts that boot run.sh directly (custom startup, entrypoint override)
# still self-update. Safety rules:
#   * HTTPS-only: plain-http update URLs are rejected (tampered downloads).
#   * Skipped when the entrypoint already ran the check this boot (EGG_UPDATE_CHECKED)
#     so panels boot fast instead of paying for a second network round-trip.
#   * The launcher currently executing is NEVER overwritten in place (bash
#     reads scripts lazily - overwriting the running file corrupts execution).
#     A newer copy is staged at .potenfyr/run.sh.update with its sha256 in
#     .potenfyr/launcher-hash, which the entrypoint promotes & verifies on the
#     NEXT boot.
#   * URL ending in .sh replaces the launcher directly; any other URL is
#     treated as the raw egg JSON and the launcher is refreshed from the same
#     branch. Any failure is non-fatal: the installed launcher keeps running.
if [ "${EGG_UPDATE_CHECKED:-0}" != "1" ]; then
    EGG_UPDATE_URL="${EGG_UPDATE_URL:-https://raw.githubusercontent.com/PotenFYR-Studios/Prog-Language-Eggs/main/egg-programming-multi.json}"
    AUTO_UPDATE_EGG="${AUTO_UPDATE_EGG:-1}"

    # Servers created before these variables existed: persist the defaults so
    # the variables show up (and stay editable) in the panel's Startup tab.
    if ! grep -qE '^EGG_UPDATE_URL=' "${CONF_FILE}" 2>/dev/null; then
        save_conf EGG_UPDATE_URL "${EGG_UPDATE_URL}"
    fi
    if ! grep -qE '^AUTO_UPDATE_EGG=' "${CONF_FILE}" 2>/dev/null; then
        save_conf AUTO_UPDATE_EGG "${AUTO_UPDATE_EGG}"
    fi

    if [ "${AUTO_UPDATE_EGG}" = "1" ] && [ -n "${EGG_UPDATE_URL}" ] && command -v curl >/dev/null 2>&1; then
        if [[ "${EGG_UPDATE_URL}" =~ ^https:// ]]; then
            _self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
            # Stage updates in /opt/potenfyr - container-local, user-writable,
            # and outside the user's data volume so launcher internals never
            # appear under /home/container. Older images without the dir fall
            # back to the workspace path (entrypoint migrates it out on boot).
            _egg_state="/opt/potenfyr"
            mkdir -p "${_egg_state}" 2>/dev/null || true
            if ! [ -w "${_egg_state}" ]; then
                _egg_state="${WORK_DIR}/.potenfyr"
                mkdir -p "${_egg_state}" 2>/dev/null || true
            fi
            _egg_target="${_egg_state}/run.sh"
            _egg_stage="${_egg_state}/run.sh.update"
            _egg_hashfile="${_egg_state}/egg-hash"
            _egg_lhash="${_egg_state}/launcher-hash"
            _egg_tmp="$(mktemp 2>/dev/null || echo "/tmp/potenfyr-egg.$$")"
            if curl -fsSL --retry 1 --max-time 15 "${EGG_UPDATE_URL}" -o "${_egg_tmp}" 2>/dev/null && [ -s "${_egg_tmp}" ]; then
                _egg_hash_new="$(sha256sum "${_egg_tmp}" 2>/dev/null | cut -d' ' -f1)"
                _egg_hash_old="$(cat "${_egg_hashfile}" 2>/dev/null || cat /etc/potenfyr-egg-hash 2>/dev/null || true)"
                if [ -n "${_egg_hash_new}" ] && [ "${_egg_hash_new}" != "${_egg_hash_old}" ]; then
                    case "${EGG_UPDATE_URL}" in
                        *.sh)
                            _egg_src="${_egg_tmp}"
                            ;;
                        *)
                            _base="${EGG_UPDATE_URL%/*}"
                            _egg_src=""
                            if curl -fsSL --retry 1 --max-time 15 "${_base}/run.sh" -o "${_egg_tmp}.run" 2>/dev/null && [ -s "${_egg_tmp}.run" ] && grep -q "PotenFYR Studios" "${_egg_tmp}.run" 2>/dev/null; then
                                sed -i 's/\r$//' "${_egg_tmp}.run" 2>/dev/null || true
                                _egg_src="${_egg_tmp}.run"
                            else
                                warn "Egg update detected but launcher refresh failed - continuing with installed launcher."
                            fi
                            ;;
                    esac
                    if [ -n "${_egg_src:-}" ]; then
                        # Never overwrite the launcher file we are executing.
                        if [ "${_self}" = "$(readlink -f "${_egg_target}" 2>/dev/null || echo "${_egg_target}")" ]; then
                            _egg_target="${_egg_stage}"
                        fi
                        if cp "${_egg_src}" "${_egg_target}" 2>/dev/null; then
                            chmod +x "${_egg_target}" 2>/dev/null || true
                            echo "${_egg_hash_new}" > "${_egg_hashfile}" 2>/dev/null || true
                            # Record the launcher's own sha256 so the entrypoint
                            # can verify integrity before ever executing it.
                            sha256sum "${_egg_target}" 2>/dev/null | cut -d' ' -f1 > "${_egg_lhash}" 2>/dev/null || true
                            ok "Egg updated from EGG_UPDATE_URL - new launcher becomes active on next start."
                        else
                            warn "Egg self-update failed (target not writable): ${_egg_target}"
                        fi
                    fi
                    rm -f "${_egg_tmp}.run" 2>/dev/null || true
                else
                    info "Egg is up to date."
                fi
            else
                warn "EGG_UPDATE_URL fetch failed - continuing with installed launcher."
            fi
            rm -f "${_egg_tmp}" 2>/dev/null || true
            unset _egg_tmp _egg_src _egg_hash_new _egg_hash_old _egg_target _egg_stage _egg_hashfile _egg_lhash _egg_state _base _self
        else
            warn "EGG_UPDATE_URL must be an https:// URL - self-update disabled for safety."
        fi
    fi
fi

# -----------------------------------------------------------------------------
# 1.1 Git Synchronization
# -----------------------------------------------------------------------------
phase "Git Synchronization"
if [ -n "${GIT_REPO}" ]; then
    if ! valid_git_url "${GIT_REPO}"; then
        fail "GIT_REPO is not a valid https/ssh Git URL: $(redact_url "${GIT_REPO}")"
    fi
    log "Checking Git repository integration..."
    sync_git_repo
fi

# -----------------------------------------------------------------------------
# 2. Interactive Setup Wizard (Interactive TTY vs Non-Interactive)
# -----------------------------------------------------------------------------
FILE_COUNT=$(find . -mindepth 1 -maxdepth 1 -not -name '.*' -not -name 'run.sh' -not -name 'entrypoint.sh' -not -name 'install.sh' -not -name 'install-runtime.sh' 2>/dev/null | wc -l)

if [ "${FILE_COUNT}" -eq 0 ] && [ -z "${STARTER_TEMPLATE}" ]; then
    if [ "${LANGUAGE}" != "auto" ] && [ -n "${LANGUAGE}" ] && [ "${LANGUAGE}" != "custom" ]; then
        STARTER_TEMPLATE="${LANGUAGE}"
        log "Empty workspace detected with language '${LANGUAGE}'. Auto-scaffolding starter project..."
    elif [ -t 0 ]; then
        printf "\n${C_MAGENTA}${C_BOLD}===============================================================================${C_RESET}\n"
        printf "${C_CYAN}${C_BOLD}  Empty workspace detected! Choose a language to scaffold a starter project:${C_RESET}\n"
        printf "${C_MAGENTA}${C_BOLD}===============================================================================${C_RESET}\n"
        printf "  ${C_BOLD}1)${C_RESET} Node.js / Express (JavaScript HTTP Server)\n"
        printf "  ${C_BOLD}2)${C_RESET} Bun (Fast TypeScript / JavaScript Server)\n"
        printf "  ${C_BOLD}3)${C_RESET} TypeScript (Node.js + ts-node / tsx)\n"
        printf "  ${C_BOLD}4)${C_RESET} Python (FastAPI / Flask HTTP Server)\n"
        printf "  ${C_BOLD}5)${C_RESET} Java (Maven / Spring Boot / Spark)\n"
        printf "  ${C_BOLD}6)${C_RESET} Go / Golang (High Performance HTTP Server)\n"
        printf "  ${C_BOLD}7)${C_RESET} Rust (Axum / Actix Web Server)\n"
        printf "  ${C_BOLD}8)${C_RESET} C / C++ (High Performance Native Server)\n"
        printf "  ${C_BOLD}9)${C_RESET} PHP (Built-in Web Server)\n"
        printf "  ${C_BOLD}10)${C_RESET} .NET / C# (ASP.NET Core Web API)\n"
        printf "  ${C_BOLD}11)${C_RESET} Ruby (Sinatra / Puma Server)\n"
        printf "  ${C_BOLD}12)${C_RESET} Static HTML / React / Frontend Website\n"
        printf "\n"

        read -r -t 15 -p "$(echo -e "${C_YELLOW}${C_BOLD}Select choice [1-12] (Default 1): ${C_RESET}")" CHOICE 2>/dev/null || CHOICE="1"
        CHOICE="${CHOICE:-1}"

        case "${CHOICE}" in
            1) STARTER_TEMPLATE="nodejs" ;;
            2) STARTER_TEMPLATE="bun" ;;
            3) STARTER_TEMPLATE="typescript" ;;
            4) STARTER_TEMPLATE="python" ;;
            5) STARTER_TEMPLATE="java" ;;
            6) STARTER_TEMPLATE="golang" ;;
            7) STARTER_TEMPLATE="rust" ;;
            8) STARTER_TEMPLATE="c-cpp" ;;
            9) STARTER_TEMPLATE="php" ;;
            10) STARTER_TEMPLATE="dotnet" ;;
            11) STARTER_TEMPLATE="ruby" ;;
            12) STARTER_TEMPLATE="static" ;;
            *) STARTER_TEMPLATE="nodejs" ;;
        esac
    else
        log "Non-interactive environment detected. Defaulting to Node.js starter."
        STARTER_TEMPLATE="nodejs"
    fi
fi

# -----------------------------------------------------------------------------
# 3. Apply Starter Template if requested
# -----------------------------------------------------------------------------
if [ -n "${STARTER_TEMPLATE}" ] && [ "${STARTER_TEMPLATE}" != "empty" ]; then
    log "Generating starter project for template: '${STARTER_TEMPLATE}'..."
    case "${STARTER_TEMPLATE}" in
        nodejs|javascript|js)
            cat << 'EOF' > package.json
{
  "name": "potenfyr-node-server",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {}
}
EOF
            cat << 'EOF' > index.js
const http = require('http');
const port = process.env.SERVER_PORT || process.env.PORT || process.env.FEATHER_PORT || 8080;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'online',
    message: 'Hello from PotenFYR Multi-Language Eggs!',
    runtime: `Node.js ${process.version}`,
    timestamp: new Date().toISOString()
  }, null, 2));
});

server.listen(port, '0.0.0.0', () => {
  console.log(`[PotenFYR] Node.js server listening on port ${port}`);
});
EOF
            LANGUAGE="nodejs"
            MAIN_FILE="index.js"
            ;;

        bun)
            cat << 'EOF' > index.ts
const port = Number(process.env.SERVER_PORT || process.env.PORT || process.env.FEATHER_PORT || 8080);

console.log(`[PotenFYR] Bun HTTP server listening on port ${port}`);

Bun.serve({
  port: port,
  fetch(req) {
    return new Response(JSON.stringify({
      status: "online",
      message: "Hello from PotenFYR Bun Egg!",
      runtime: `Bun ${Bun.version}`,
      url: req.url,
      timestamp: new Date().toISOString()
    }, null, 2), {
      headers: { "Content-Type": "application/json" }
    });
  }
});
EOF
            LANGUAGE="bun"
            MAIN_FILE="index.ts"
            [ "${RUNNER}" = "auto" ] || [ -z "${RUNNER}" ] && RUNNER="bun"
            ;;

        typescript|ts)
            cat << 'EOF' > package.json
{
  "name": "potenfyr-typescript-server",
  "version": "1.0.0",
  "main": "src/index.ts",
  "scripts": {
    "start": "ts-node src/index.ts",
    "build": "tsc"
  },
  "dependencies": {},
  "devDependencies": {
    "typescript": "^5.4.0",
    "@types/node": "^20.0.0",
    "ts-node": "^10.9.2"
  }
}
EOF
            cat << 'EOF' > tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "moduleResolution": "node",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "outDir": "./dist"
  },
  "include": ["src/**/*"]
}
EOF
            mkdir -p src
            cat << 'EOF' > src/index.ts
import * as http from 'http';

const port = process.env.SERVER_PORT || process.env.PORT || process.env.FEATHER_PORT || 8080;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'online',
    message: 'Hello from PotenFYR TypeScript Egg!',
    runtime: `Node.js ${process.version} + TypeScript`,
    timestamp: new Date().toISOString()
  }, null, 2));
});

server.listen(Number(port), '0.0.0.0', () => {
  console.log(`[PotenFYR] TypeScript server listening on port ${port}`);
});
EOF
            LANGUAGE="typescript"
            MAIN_FILE="src/index.ts"
            [ "${RUNNER}" = "auto" ] || [ -z "${RUNNER}" ] && RUNNER="tsx"
            ;;

        python|py)
            cat << 'EOF' > requirements.txt
# Add python dependencies
EOF
            cat << 'EOF' > main.py
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from datetime import datetime

PORT = int(os.environ.get("SERVER_PORT", os.environ.get("PORT", os.environ.get("FEATHER_PORT", 8080))))

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = {
            "status": "online",
            "message": "Hello from PotenFYR Python Egg!",
            "python_version": os.sys.version,
            "timestamp": datetime.utcnow().isoformat()
        }
        self.wfile.write(json.dumps(response, indent=2).encode('utf-8'))

print(f"[PotenFYR] Python HTTP server listening on port {PORT}")
httpd = HTTPServer(('0.0.0.0', PORT), RequestHandler)
httpd.serve_forever()
EOF
            LANGUAGE="python"
            MAIN_FILE="main.py"
            ;;

        golang|go)
            cat << 'EOF' > go.mod
module potenfyr-server

go 1.22
EOF
            cat << 'EOF' > main.go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"runtime"
	"time"
)

type StatusResponse struct {
	Status    string `json:"status"`
	Message   string `json:"message"`
	GoVersion string `json:"go_version"`
	Time      string `json:"timestamp"`
}

func main() {
	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = os.Getenv("PORT")
	}
	if port == "" {
		port = os.Getenv("FEATHER_PORT")
	}
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		resp := StatusResponse{
			Status:    "online",
			Message:   "Hello from PotenFYR Golang Egg!",
			GoVersion: runtime.Version(),
			Time:      time.Now().UTC().Format(time.RFC3339),
		}
		json.NewEncoder(w).Encode(resp)
	})

	fmt.Printf("[PotenFYR] Go HTTP server listening on port %s\n", port)
	if err := http.ListenAndServe("0.0.0.0:"+port, nil); err != nil {
		fmt.Printf("Server failed: %v\n", err)
	}
}
EOF
            LANGUAGE="golang"
            MAIN_FILE="main.go"
            ;;

        rust|rs)
            mkdir -p src
            cat << 'EOF' > Cargo.toml
[package]
name = "potenfyr-rust-server"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF
            cat << 'EOF' > src/main.rs
use std::env;
use std::io::Write;
use std::net::TcpListener;

fn main() {
    let port = env::var("SERVER_PORT")
        .or_else(|_| env::var("PORT"))
        .or_else(|_| env::var("FEATHER_PORT"))
        .unwrap_or_else(|_| "8080".to_string());
    let addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&addr).expect("Could not bind port");
    println!("[PotenFYR] Rust server listening on http://{}", addr);

    for stream in listener.incoming() {
        if let Ok(mut stream) = stream {
            let body = "{\"status\":\"online\",\"message\":\"Hello from PotenFYR Rust Egg!\"}";
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        }
    }
}
EOF
            LANGUAGE="rust"
            ;;

        static|html)
            cat << 'EOF' > index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PotenFYR Static Server</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .card { background: #1e293b; padding: 2.5rem; border-radius: 1rem; box-shadow: 0 10px 25px rgba(0,0,0,0.5); text-align: center; border: 1px solid #334155; }
    h1 { color: #38bdf8; margin-top: 0; }
    p { color: #94a3b8; font-size: 1.1rem; }
    .badge { display: inline-block; background: #0284c7; color: white; padding: 0.25rem 0.75rem; border-radius: 9999px; font-size: 0.85rem; font-weight: 600; margin-top: 1rem; }
  </style>
</head>
<body>
  <div class="card">
    <h1>🚀 PotenFYR Static Server</h1>
    <p>Your static website / SPA is live and running at peak performance!</p>
    <div class="badge">Multi-Language Eggs</div>
  </div>
</body>
</html>
EOF
            LANGUAGE="static"
            ;;
    esac
    ok "Starter template generated"
fi

# Start the panel stop-command watcher only now: before it, stdin belongs to
# the interactive setup wizard (first boot in an empty workspace) and to git
# credential prompts. From here on every long phase (dep sync, build, app run)
# is covered, and stop commands typed by the daemon land with the watcher.
start_stop_watcher

# -----------------------------------------------------------------------------
# 4. Production Multi-Process Supervisor (Procfile support)
# -----------------------------------------------------------------------------
# Built for multi-layer / microservice-style apps inside ONE container:
#
#   Procfile:
#     web:      node server.js
#     worker:   wait_port 127.0.0.1 5432 60 && node worker.js
#     api:      python -m uvicorn api:app --port $SERVER_PORT
#
#   * SUPERVISOR=procfile forces this mode even when a single language is
#     detected; SUPERVISOR=single disables it entirely (default: auto).
#   * PROCFILE_RESTART=1 (default) restarts crashed processes with backoff,
#     giving up after PROCFILE_MAX_RESTARTS within the backoff window.
#   * PROCFILE_LOGS=1 mirrors each process stream to .logs/processes/<name>.log
#   * wait_port <host> <port> [timeout_s] is exported for startup ordering
#     (e.g. wait for an external database before booting the web layer).
#   * SIGTERM/SIGINT relay to ALL children for clean panel stops.
# -----------------------------------------------------------------------------

SUPERVISOR="${SUPERVISOR:-auto}"
PROCFILE_RESTART="${PROCFILE_RESTART:-1}"
PROCFILE_MAX_RESTARTS="${PROCFILE_MAX_RESTARTS:-5}"
PROCFILE_LOGS="${PROCFILE_LOGS:-0}"

wait_port() { # wait_port <host> <port> [timeout_seconds=30]
    local host="$1" port="$2" timeout="${3:-30}" waited=0
    while [ "${waited}" -lt "${timeout}" ]; do
        if (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; then
            exec 3>&- 3<&- 2>/dev/null || true
            return 0
        fi
        sleep 1; waited=$((waited+1))
    done
    warn "wait_port: ${host}:${port} not reachable within ${timeout}s."
    return 1
}
export -f wait_port

PROC_PIDS=""; PROC_NAMES=""; PROC_FAILED=""

proc_shutdown_all() {
    local p
    for p in ${PROC_PIDS}; do
        [ -n "${p}" ] && [ "${p}" -gt 1 ] 2>/dev/null && terminate_process_tree "${p}" 4
    done
    PROC_PIDS=""
}

run_procfile() {
    local procfile="Procfile"
    [ -f "${procfile}" ] || return 1

    log "Procfile detected! Launching Production Multi-Process Supervisor..."
    mkdir -p "${WORK_DIR}/.logs/processes" 2>/dev/null || true

    declare -A RESTART_COUNT FIRST_SEEN
    while IFS=':' read -r name cmd || [ -n "$name" ]; do
        case "$name" in \#*) continue ;; esac
        [ -z "$name" ] && continue
        cmd=$(echo "$cmd" | sed -e 's/^[[:space:]]*//')
        [ -z "$cmd" ] && continue

        log "Starting process: [${name}] -> ${cmd}"
        RESTART_COUNT["${name}"]=0
        FIRST_SEEN["${name}"]=$(date +%s)
        (
            export PROCESS_NAME="${name}"
            export SERVER_PORT PORT FEATHER_PORT PUFFER_PORT HTTP_PORT
            if [ "${PROCFILE_LOGS}" = "1" ]; then
                stdbuf -oL -eL eval "${cmd}" 2>&1 \
                    | tee -a "${WORK_DIR}/.logs/processes/${name}.log" \
                    | while IFS= read -r line; do printf "\033[1;36m[%s]\033[0m %s\n" "${name}" "${line}"; done
            else
                eval "${cmd}" 2>&1 \
                    | while IFS= read -r line; do printf "\033[1;36m[%s]\033[0m %s\n" "${name}" "${line}"; done
            fi
        ) &
        PROC_PIDS="${PROC_PIDS} $!"
        PROC_NAMES="${PROC_NAMES} ${name}"
    done < "${procfile}"

    # Supervise: restart crashed children (backoff), report, and exit when all dead
    while [ "${RUN_LOOP:-1}" -eq 1 ]; do
        sleep 1
        [ "${RUN_LOOP:-1}" -eq 0 ] && break
        local idx=0 alive=0 new_pids="" new_names=""
        for p in ${PROC_PIDS}; do
            idx=$((idx+1))
            local n; n=$(echo "${PROC_NAMES}" | awk '{print $'"${idx}"'}')
            if kill -0 "${p}" 2>/dev/null; then
                alive=$((alive+1)); new_pids="${new_pids} ${p}"; new_names="${new_names} ${n}"
                continue
            fi
            wait "${p}" 2>/dev/null; local rc=$?
            [ "${RUN_LOOP:-1}" = "0" ] && continue   # shutting down: don't restart
            if [ "${PROCFILE_RESTART}" = "1" ]; then
                local now count
                now=$(date +%s)
                count=$(( ${RESTART_COUNT["${n}"]:-0} + 1 ))
                RESTART_COUNT["${n}"]="${count}"
                if [ "${count}" -gt "${PROCFILE_MAX_RESTARTS}" ]; then
                    warn "[${n}] exceeded ${PROCFILE_MAX_RESTARTS} restart attempts - giving up on this process."
                    PROC_FAILED="${PROC_FAILED} ${n}"
                    continue
                fi
                warn "[${n}] exited (code ${rc}). Restarting (attempt ${count}/${PROCFILE_MAX_RESTARTS}) in $((count))s..."
                sleep "${count}"   # linear backoff: 1s, 2s, 3s...
                (
                    export PROCESS_NAME="${n}"
                    eval "$(grep -E "^${n}:" "${procfile}" | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//')" 2>&1 \
                        | while IFS= read -r line; do printf "\033[1;36m[%s]\033[0m %s\n" "${n}" "${line}"; done
                ) &
                new_pids="${new_pids} $!"; new_names="${new_names} ${n}"
            else
                warn "[${n}] exited (code ${rc}). PROCFILE_RESTART=0 - not restarting."
            fi
        done
        PROC_PIDS="${new_pids}"; PROC_NAMES="${new_names}"
        if [ "${alive}" = "0" ]; then
            if [ -n "${PROC_FAILED// /}" ]; then
                fail "All supervised processes have stopped. See .logs/processes/ for details."
            fi
            break
        fi
    done
    ok "All supervised processes exited cleanly."
    exit 0
}

case "${SUPERVISOR}" in
    procfile|multi|all)
        run_procfile || warn "SUPERVISOR=procfile requested but no Procfile found - continuing single-process."
        ;;
    single|none) : ;;   # explicitly disabled
    *)
        if [ -f "Procfile" ] && [ "${LANGUAGE}" = "auto" ] && [ -z "${CUSTOM_COMMAND}" ]; then
            run_procfile
        fi
        ;;
esac

# -----------------------------------------------------------------------------
# 5. Project & Language Auto-Detection Engine
# -----------------------------------------------------------------------------
detect_language() {
    if [ "${LANGUAGE}" != "auto" ] && [ -n "${LANGUAGE}" ]; then
        echo "${LANGUAGE}" | tr '[:upper:]' '[:lower:]'
        return
    fi

    if [ -f "index.html" ] || [ -f "dist/index.html" ] || [ -f "build/index.html" ] || [ -f "public/index.html" ]; then
        if [ ! -f "package.json" ] && [ ! -f "main.py" ] && [ ! -f "main.go" ] && [ ! -f "Cargo.toml" ] && [ ! -f "pom.xml" ]; then
            echo "static"; return
        fi
    fi

    if [ -f "bun.lockb" ] || [ -f "bunfig.toml" ]; then
        echo "bun"; return
    fi
    if [ -f "deno.json" ] || [ -f "deno.jsonc" ]; then
        echo "deno"; return
    fi
    if [ -f "package.json" ]; then
        if grep -qE '"typescript"|"ts-node"|"tsx"' package.json 2>/dev/null; then
            echo "typescript"; return
        fi
        echo "nodejs"; return
    fi
    if [ -f "requirements.txt" ] || [ -f "Pipfile" ] || [ -f "pyproject.toml" ] || [ -f "main.py" ] || [ -f "app.py" ]; then
        echo "python"; return
    fi
    if [ -f "go.mod" ] || [ -f "main.go" ]; then
        echo "golang"; return
    fi
    if [ -f "Cargo.toml" ]; then
        echo "rust"; return
    fi
    if [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ] || ls *.jar 1>/dev/null 2>&1; then
        echo "java"; return
    fi
    if ls *.csproj 1>/dev/null 2>&1 || ls *.sln 1>/dev/null 2>&1 || [ -f "Program.cs" ]; then
        echo "dotnet"; return
    fi
    if [ -f "composer.json" ] || [ -f "index.php" ]; then
        echo "php"; return
    fi
    if [ -f "Gemfile" ] || ls *.rb 1>/dev/null 2>&1; then
        echo "ruby"; return
    fi
    if [ -f "Makefile" ] || [ -f "CMakeLists.txt" ] || ls *.cpp 1>/dev/null 2>&1 || ls *.c 1>/dev/null 2>&1; then
        echo "c-cpp"; return
    fi
    if [ -f "build.zig" ] || ls *.zig 1>/dev/null 2>&1; then
        echo "zig"; return
    fi
    if [ -f "Package.swift" ] || ls *.swift 1>/dev/null 2>&1; then
        echo "swift"; return
    fi
    if [ -f "pubspec.yaml" ] || ls *.dart 1>/dev/null 2>&1; then
        echo "dart"; return
    fi
    if [ -f "mix.exs" ] || ls *.ex 1>/dev/null 2>&1; then
        echo "elixir"; return
    fi
    if ls *.lua 1>/dev/null 2>&1; then
        echo "lua"; return
    fi
    if ls *.ts 1>/dev/null 2>&1; then
        echo "typescript"; return
    fi
    if ls *.js 1>/dev/null 2>&1; then
        echo "nodejs"; return
    fi

    # User shell scripts (skip system egg runner scripts)
    for sh_file in $(ls *.sh 2>/dev/null || true); do
        case "${sh_file}" in
            entrypoint.sh|run.sh|install.sh|install-runtime.sh) ;;
            *) echo "bash"; return ;;
        esac
    done

    echo "nodejs"
}

DETECTED_LANG=$(detect_language)
log "Target Language / Runtime: ${C_BOLD}${DETECTED_LANG}${C_RESET}"

# -----------------------------------------------------------------------------
# 5.5 Runtime Version Resolution & Per-Version Environment Isolation
# -----------------------------------------------------------------------------
# * RUNTIME_VERSION is validated & resolved ONCE through live upstream feeds:
#     keywords: latest stable lts alpha beta rc preview nightly canary dev
#     versions: 22 | 22.1 | 22.1.4 (v-prefix tolerated) - garbage fails fast.
# * Each language+series keeps its own environment folder under .environments/
#   so switching languages or major versions NEVER deletes or corrupts another:
#
#     .environments/<language>/<series>/    caches, homes, shims, tool state
#     .environments/active                  last used instance (marker)
#     .environments/.resolved/<lang>        resolved concrete version cache
#
#   Same series, newer patch -> compatible: SAME folder reused (info message).
#   New series/major         -> breaking: NEW folder created, old preserved,
#                               console warning lists old folders + sizes and
#                               how to delete them manually (nothing is auto-
#                               deleted, by design).
# -----------------------------------------------------------------------------

ENV_ROOT="${WORK_DIR}/.environments"
ACTIVE_ENV_FILE="${ENV_ROOT}/active"
RESOLVED_CACHE_DIR="${ENV_ROOT}/.resolved"
mkdir -p "${ENV_ROOT}" "${RESOLVED_CACHE_DIR}" 2>/dev/null || true

resolve_runtime_version() {
    # Resolves once per boot; cached under .environments/.resolved/<lang>
    local lang="$1" req="${RUNTIME_VERSION:-latest}" cache_file out rc=0
    [ -z "${req}" ] && req="latest"
    case "${req}" in latest|stable|lts|auto) cache_file="" ;; esac

    local resolver="/usr/local/bin/resolve-version.sh"
    [ -f "${resolver}" ] || resolver="/resolve-version.sh"
    if [ ! -f "${resolver}" ]; then
        mkdir -p /tmp/potenfyr 2>/dev/null || true
        curl -fsSL --retry 3 --connect-timeout 10 \
            "https://raw.githubusercontent.com/PotenFYR-Studios/Prog-Language-Eggs/main/resolve-version.sh" \
            -o /tmp/potenfyr/resolve-version.sh 2>/dev/null || true
        resolver="/tmp/potenfyr/resolve-version.sh"
    fi
    [ -f "${resolver}" ] || { warn "Version resolver unavailable; continuing with raw request '${req}'."; echo "${req}"; return 0; }

    if ! out=$(bash "${resolver}" "${lang}" "${req}"); then
        rc=$?
        warn "Version request '${req}' rejected for ${lang}. Falling back to installer defaults."
        echo ""
        return $rc
    fi
    printf '%s\n' "${out}"
    printf '%s\n' "${out}" > "${RESOLVED_CACHE_DIR}/${lang}" 2>/dev/null || true
}

env_series_of() { # compatibility domain: which versions share one environment folder
    local lang="$1" v="${2:-}"
    local r="${v#v}"
    case "${lang}" in
        nodejs|javascript|js|typescript|ts)
            [[ "${r}" =~ ^[0-9]+ ]] && echo "node${r%%.*}" || echo "current" ;;
        python|py)
            if [[ "${r}" =~ ^[0-9]+\.[0-9]+ ]]; then echo "py${r%.*}"; elif [[ "${r}" =~ ^[0-9]+ ]]; then echo "py${r}.x"; else echo "current"; fi ;;
        golang|go)
            if [[ "${r}" =~ ^[0-9]+\.[0-9]+ ]]; then echo "go${r%.*}"; else echo "current"; fi ;;
        java)
            [[ "${r}" =~ ^[0-9]+ ]] && echo "jdk${r%%.*}" || echo "current" ;;
        dotnet)
            if [[ "${r}" =~ ^[0-9]+\.[0-9]+ ]]; then echo "net${r%.*}"; elif [[ "${r}" =~ ^[0-9]+$ ]]; then echo "net${r}.0"; else echo "current"; fi ;;
        bun|deno|php|ruby|zig|dart|swift|julia|nim)
            [[ "${r}" =~ ^[0-9]+ ]] && echo "${lang}-${r%%.*}" || echo "current" ;;
        rust)
            case "${r}" in stable|beta|nightly) echo "rust-${r}" ;; *) [[ "${r}" =~ ^[0-9]+\.[0-9]+ ]] && echo "rust-${r%.*}" || echo "rust-stable" ;; esac ;;
        *)
            echo "default" ;;
    esac
}

read_env_active() {
    ENV_PREV_LANG=""; ENV_PREV_SERIES=""
    [ -f "${ACTIVE_ENV_FILE}" ] || return 1
    local line
    line=$(head -n1 "${ACTIVE_ENV_FILE}" 2>/dev/null | tr -d '\r')
    ENV_PREV_LANG="$(echo "${line}" | awk -F'|' '{print $1}')"
    ENV_PREV_SERIES="$(echo "${line}" | awk -F'|' '{print $2}')"
    [ -n "${ENV_PREV_LANG}" ]
}

scan_retained_environments() {
    local found="" d l s size
    for d in "${ENV_ROOT}"/*/*; do
        [ -d "${d}" ] || continue
        l="$(basename "$(dirname "${d}")")"
        s="$(basename "${d}")"
        [ "${l}" = "${DETECTED_LANG}" ] && [ "${s}" = "${ENV_SERIES}" ] && continue
        find "${d}" -mindepth 1 2>/dev/null | grep -q . || continue
        size=$(du -sh "${d}" 2>/dev/null | awk '{print $1}')
        found="${found}    - .environments/${l}/${s} (${size})\n"
    done
    if [ -n "${found}" ]; then
        printf "\n" >&2
        printf "${C_YELLOW}${C_BOLD}[PotenFYR][!] RETAINED ENVIRONMENTS FROM PREVIOUS CONFIGURATIONS${C_RESET}\n" >&2
        printf "${C_YELLOW}  Kept untouched on purpose (nothing is auto-deleted):%b${C_RESET}\n" "${found}" >&2
        printf "${C_DIM}    Delete any of these manually via the panel File Manager when you no longer need them.${C_RESET}\n" >&2
        printf "\n" >&2
    fi
}

setup_isolated_environment() {
    local resolved_ver=""
    if resolved_ver=$(resolve_runtime_version "${DETECTED_LANG}"); then
        [ -n "${resolved_ver}" ] && RUNTIME_VERSION_RESOLVED="${resolved_ver}"
    fi
    : "${RUNTIME_VERSION_RESOLVED:=${RUNTIME_VERSION:-}}"
    export RUNTIME_VERSION_RESOLVED

    ENV_SERIES=$(env_series_of "${DETECTED_LANG}" "${RUNTIME_VERSION_RESOLVED}")
    ENV_DIR="${ENV_ROOT}/${DETECTED_LANG}/${ENV_SERIES}"
    mkdir -p "${ENV_DIR}/bin" 2>/dev/null || true

    read_env_active || true
    if [ -n "${ENV_PREV_LANG}" ]; then
        if [ "${ENV_PREV_LANG}" = "${DETECTED_LANG}" ] && [ "${ENV_PREV_SERIES}" = "${ENV_SERIES}" ]; then
            info "Environment reused: ${DETECTED_LANG} [${ENV_SERIES}] (compatible series)."
        elif [ "${ENV_PREV_LANG}" != "${DETECTED_LANG}" ]; then
            printf "\n" >&2
            printf "${C_YELLOW}${C_BOLD}[PotenFYR][!] LANGUAGE CHANGE DETECTED (%s -> %s)${C_RESET}\n" "${ENV_PREV_LANG}" "${DETECTED_LANG}" >&2
            printf "${C_YELLOW}  A separate environment was created: .environments/%s/%s${C_RESET}\n" "${DETECTED_LANG}" "${ENV_SERIES}" >&2
            printf "${C_YELLOW}  Your previous %s environment is preserved at .environments/%s/${C_RESET}\n" "${ENV_PREV_LANG}" "${ENV_PREV_LANG}" >&2
            printf "${C_DIM}  Nothing was deleted. Remove old environments manually when no longer needed.${C_RESET}\n" >&2
            printf "\n" >&2
        else
            printf "\n" >&2
            printf "${C_YELLOW}${C_BOLD}[PotenFYR][!] BREAKING VERSION CHANGE (%s: %s -> %s)${C_RESET}\n" "${DETECTED_LANG}" "${ENV_PREV_SERIES}" "${ENV_SERIES}" >&2
            printf "${C_YELLOW}  Major-version boundaries get their OWN environment folder.${C_RESET}\n" >&2
            printf "${C_YELLOW}  New environment : .environments/%s/%s${C_RESET}\n" "${DETECTED_LANG}" "${ENV_SERIES}" >&2
            printf "${C_YELLOW}  Previous kept at: .environments/%s/%s (safe to delete manually later)${C_RESET}\n" "${DETECTED_LANG}" "${ENV_PREV_SERIES}" >&2
            printf "\n" >&2
        fi
        scan_retained_environments
    fi

    # Route toolchain caches/state into the isolated environment folder
    case "${DETECTED_LANG}" in
        nodejs|javascript|js|typescript|ts|bun)
            export NPM_CONFIG_CACHE="${ENV_DIR}/npm-cache"
            export BUN_INSTALL="${ENV_DIR}/bun-home"
            ;;
        python|py)
            export PIP_CACHE_DIR="${ENV_DIR}/pip-cache"
            export UV_CACHE_DIR="${ENV_DIR}/uv-cache"
            ;;
        golang|go)
            export GOMODCACHE="${ENV_DIR}/gomodcache"
            export GOCACHE="${ENV_DIR}/gocache"
            ;;
        rust)
            export CARGO_HOME="${ENV_DIR}/cargo-home"
            ;;
        java)
            export GRADLE_USER_HOME="${ENV_DIR}/gradle"
            mkdir -p "${ENV_DIR}/m2" 2>/dev/null || true
            [ -w "${HOME:-/home/container}" ] && ln -sfn "${ENV_DIR}/m2" "${HOME:-/home/container}/.m2" 2>/dev/null || true
            ;;
        dotnet)
            export NUGET_PACKAGES="${ENV_DIR}/nuget"
            export DOTNET_CLI_HOME="${ENV_DIR}/dotnet-home"
            ;;
        php)     export COMPOSER_HOME="${ENV_DIR}/composer" ;;
        ruby)    export GEM_HOME="${ENV_DIR}/gems" ;;
        dart)    export PUB_CACHE="${ENV_DIR}/pub" ;;
        deno)    export DENO_DIR="${ENV_DIR}/deno" ;;
        zig)     export ZIG_GLOBAL_CACHE_DIR="${ENV_DIR}/zig-cache" ;;
    esac
    export PATH="${ENV_DIR}/bin:${PATH}"

    printf '%s|%s|%s\n' "${DETECTED_LANG}" "${ENV_SERIES}" "${RUNTIME_VERSION_RESOLVED}" > "${ACTIVE_ENV_FILE}" 2>/dev/null || \
        warn "Could not write environment marker (${ACTIVE_ENV_FILE})."
}

setup_isolated_environment


if [ -n "${CUSTOM_RUNTIME_URL:-}" ]; then
    if ! valid_http_url "${CUSTOM_RUNTIME_URL}"; then
        fail "CUSTOM_RUNTIME_URL must be a valid http(s) URL (got: $(redact_url "${CUSTOM_RUNTIME_URL}"))."
    fi
    if [ -f /usr/local/bin/install-runtime.sh ]; then
        log "Downloading and configuring custom runtime from $(redact_url "${CUSTOM_RUNTIME_URL}")..."
        /usr/local/bin/install-runtime.sh "custom" "${CUSTOM_RUNTIME_URL}" "${WORK_DIR}/.runtimes" || true
    fi
fi

# -----------------------------------------------------------------------------
# Dynamic Session-Layer PATH & Sandbox Isolation (Alternative 4 Hybrid Architecture)
# -----------------------------------------------------------------------------
build_isolated_environment() {
    local lang="${DETECTED_LANG}"
    local runner="${RUNNER:-auto}"

    # 1. Base clean system utilities
    local ISO_PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"

    # 2. Local workspace project binaries (highest priority)
    ISO_PATH="${WORK_DIR}/.local/bin:${WORK_DIR}/bin:${WORK_DIR}/node_modules/.bin:${WORK_DIR}/.venv/bin:${ISO_PATH}"
    
    # 3. User-installed local runtimes (/home/container/.runtimes/<lang>/bin)
    if [ -d "${WORK_DIR}/.runtimes" ]; then
        ISO_PATH="${WORK_DIR}/.runtimes/bin:${WORK_DIR}/.runtimes/${lang}/bin:${WORK_DIR}/.runtimes/${runner}/bin:${ISO_PATH}"
    fi

    # 4. Activate ONLY the selected isolated runtime prefix
    case "${lang}" in
        typescript|ts)
            if [ "${runner}" = "bun" ]; then
                ISO_PATH="/opt/runtimes/bun/bin:${ISO_PATH}"
            elif [ "${runner}" = "deno" ]; then
                ISO_PATH="/opt/runtimes/deno/bin:${ISO_PATH}"
            else
                ISO_PATH="/opt/runtimes/node/bin:${ISO_PATH}"
            fi
            ;;
        bun)
            ISO_PATH="/opt/runtimes/bun/bin:${ISO_PATH}"
            ;;
        deno)
            ISO_PATH="/opt/runtimes/deno/bin:${ISO_PATH}"
            ;;
        node|nodejs|javascript|js)
            ISO_PATH="/opt/runtimes/node/bin:${ISO_PATH}"
            ;;
        python|py)
            ISO_PATH="/opt/runtimes/uv/bin:/opt/runtimes/python/bin:${ISO_PATH}"
            ;;
        rust)
            ISO_PATH="/opt/cargo/bin:${ISO_PATH}"
            ;;
        golang|go)
            ISO_PATH="${WORK_DIR}/go/bin:/opt/go/bin:/opt/runtimes/go/bin:${ISO_PATH}"
            ;;
        zig)
            ISO_PATH="/opt/runtimes/zig:${ISO_PATH}"
            ;;
        dart)
            ISO_PATH="/opt/runtimes/dart-sdk/bin:${ISO_PATH}"
            ;;
        dotnet)
            ISO_PATH="/opt/dotnet:${WORK_DIR}/.dotnet:${ISO_PATH}"
            ;;
    esac

    # 5. Handle EXTRA_RUNTIMES if specified (e.g. EXTRA_RUNTIMES="python,bun")
    if [ -n "${EXTRA_RUNTIMES:-}" ]; then
        local IFS=','
        for ext in ${EXTRA_RUNTIMES}; do
            ext=$(echo "${ext}" | tr -d "[:space:]" | tr "[:upper:]" "[:lower:]")
            [ -d "/opt/runtimes/${ext}/bin" ] && ISO_PATH="/opt/runtimes/${ext}/bin:${ISO_PATH}"
            [ -d "${WORK_DIR}/.runtimes/${ext}/bin" ] && ISO_PATH="${WORK_DIR}/.runtimes/${ext}/bin:${ISO_PATH}"
        done
    fi

    export PATH="${ISO_PATH}"

    # Per-language sandbox isolation directories
    export PYTHONUSERBASE="${WORK_DIR}/.local"
    export GOPATH="${WORK_DIR}/go"
    export GOCACHE="${WORK_DIR}/.cache/go-build"
    export CARGO_HOME="${WORK_DIR}/.cargo"
    export CARGO_TARGET_DIR="${WORK_DIR}/target"
    export BUN_INSTALL="${WORK_DIR}/.bun"
    export COMPOSER_HOME="${WORK_DIR}/.composer"
    export GEM_HOME="${WORK_DIR}/.gem"
    export DOTNET_CLI_HOME="${WORK_DIR}/.dotnet"
    mkdir -p "${WORK_DIR}/.local/bin" "${WORK_DIR}/bin" "${WORK_DIR}/.cache" 2>/dev/null || true
}

# Ensure runtime toolchain is present in container, install locally if absent
ensure_local_runtime() {
    local lang="${DETECTED_LANG}"
    local runner="${RUNNER:-auto}"

    build_isolated_environment

    # Check runner requirements (e.g. user selected bun or deno engine)
    if [ "${runner}" = "bun" ] && ! command -v bun >/dev/null 2>&1; then
        log "Runner 'bun' selected but not found in PATH. Installing Bun locally..."
        local inst_script=""
        [ -f "/usr/local/bin/install-runtime.sh" ] && inst_script="/usr/local/bin/install-runtime.sh"
        [ -z "${inst_script}" ] && [ -f "/install-runtime.sh" ] && inst_script="/install-runtime.sh"
        if [ -n "${inst_script}" ]; then
            bash "${inst_script}" "bun" "latest" "${WORK_DIR}/.runtimes" || true
            export PATH="${WORK_DIR}/.runtimes/bin:${WORK_DIR}/.runtimes/bun/bin:/opt/runtimes/bun/bin:${PATH}"
        fi
    elif [ "${runner}" = "deno" ] && ! command -v deno >/dev/null 2>&1; then
        log "Runner 'deno' selected but not found in PATH. Installing Deno locally..."
        local inst_script=""
        [ -f "/usr/local/bin/install-runtime.sh" ] && inst_script="/usr/local/bin/install-runtime.sh"
        [ -z "${inst_script}" ] && [ -f "/install-runtime.sh" ] && inst_script="/install-runtime.sh"
        if [ -n "${inst_script}" ]; then
            bash "${inst_script}" "deno" "latest" "${WORK_DIR}/.runtimes" || true
            export PATH="${WORK_DIR}/.runtimes/bin:${WORK_DIR}/.runtimes/deno/bin:/opt/runtimes/deno/bin:${PATH}"
        fi
    fi

    # Check language requirements (rebuild env first so installs are seen)
    local needed=0
    case "${lang}" in
        nodejs|javascript|js)      command -v node    >/dev/null 2>&1 || needed=1 ;;
        typescript|ts)
            if [ "${runner}" = "bun" ]; then
                command -v bun >/dev/null 2>&1 || needed=1; lang="bun"
            elif [ "${runner}" = "deno" ]; then
                command -v deno >/dev/null 2>&1 || needed=1; lang="deno"
            else
                command -v node >/dev/null 2>&1 || needed=1
            fi
            ;;
        bun)                       command -v bun     >/dev/null 2>&1 || needed=1 ;;
        deno)                      command -v deno    >/dev/null 2>&1 || needed=1 ;;
        python|py)                 command -v python3 >/dev/null 2>&1 || needed=1 ;;
        golang|go)                 command -v go      >/dev/null 2>&1 || needed=1 ;;
        rust)                      command -v rustc   >/dev/null 2>&1 || needed=1 ;;
        java|jdk|openjdk)          command -v java    >/dev/null 2>&1 || needed=1 ;;
        dotnet|csharp|fsharp|vb)   command -v dotnet  >/dev/null 2>&1 || needed=1 ;;
        php)                       command -v php     >/dev/null 2>&1 || needed=1 ;;
        ruby)                      command -v ruby    >/dev/null 2>&1 || needed=1 ;;
        zig)                       command -v zig     >/dev/null 2>&1 || needed=1 ;;
        dart)                      command -v dart    >/dev/null 2>&1 || needed=1 ;;
        swift)                     command -v swift   >/dev/null 2>&1 || needed=1 ;;
        lua)                       command -v lua     >/dev/null 2>&1 || command -v luajit >/dev/null 2>&1 || needed=1 ;;
        elixir)                    command -v elixir  >/dev/null 2>&1 || needed=1 ;;
        nim)                       command -v nim     >/dev/null 2>&1 || needed=1 ;;
        gleam)                     command -v gleam   >/dev/null 2>&1 || needed=1 ;;
        odin)                      command -v odin    >/dev/null 2>&1 || needed=1 ;;
        haskell)                   command -v runghc  >/dev/null 2>&1 || command -v cabal >/dev/null 2>&1 || needed=1 ;;
        perl)                      command -v perl    >/dev/null 2>&1 || needed=1 ;;
        r)                         command -v Rscript >/dev/null 2>&1 || needed=1 ;;
        julia)                     command -v julia   >/dev/null 2>&1 || needed=1 ;;
        c-cpp|cpp|c)
            command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1 || needed=1 ;;
    esac

    if [ "${needed}" -eq 1 ]; then
        log "Runtime binary for '${lang}' not found in system PATH. Installing locally to container..."
        local inst_script=""
        if [ -f "/usr/local/bin/install-runtime.sh" ]; then
            inst_script="/usr/local/bin/install-runtime.sh"
        elif [ -f "/install-runtime.sh" ]; then
            inst_script="/install-runtime.sh"
        else
            mkdir -p /tmp/potenfyr 2>/dev/null || true
            curl -fsSL --retry 3 --connect-timeout 10 https://raw.githubusercontent.com/PotenFYR-Studios/Prog-Language-Eggs/main/install-runtime.sh -o /tmp/potenfyr/install-runtime.sh 2>/dev/null || true
            chmod +x /tmp/potenfyr/install-runtime.sh 2>/dev/null || true
            inst_script="/tmp/potenfyr/install-runtime.sh"
        fi

        if [ -f "${inst_script}" ]; then
            if ! bash "${inst_script}" "${lang}" "${RUNTIME_VERSION_RESOLVED:-${RUNTIME_VERSION:-latest}}" "${WORK_DIR}/.runtimes"; then
                warn "Runtime install failed for '${lang}' - the app may fail to start."
                warn "Check network egress, or pin RUNTIME_VERSION to an available release, then restart."
                _egg_error_log "launcher" "runtime install failed: ${lang} ${RUNTIME_VERSION_RESOLVED:-${RUNTIME_VERSION:-latest}}"
            fi
            build_isolated_environment
        else
            warn "No runtime installer available for '${lang}'. The app may fail to start."
            _egg_error_log "launcher" "no runtime installer available for '${lang}' - image may lack install-runtime.sh"
        fi
    fi
}
ensure_local_runtime

# -----------------------------------------------------------------------------
# 6. Pre-Run Hook Execution
# -----------------------------------------------------------------------------
if [ -n "${PRE_RUN_COMMAND}" ]; then
    log "Executing PRE_RUN_COMMAND: ${PRE_RUN_COMMAND}..."
    eval "${PRE_RUN_COMMAND}" || warn "Pre-run command finished with non-zero status"
    ok "Pre-run command finished"
fi

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# 6.5. Companion Runtime Resolution (EXTRA_RUNTIMES & Complex App Support)
# -----------------------------------------------------------------------------
if [ -n "${EXTRA_RUNTIMES:-}" ] && [ "${EXTRA_RUNTIMES}" != "none" ] && [ "${EXTRA_RUNTIMES}" != "auto" ]; then
    # Parallel install for fast boots; per-runtime logs under .logs/
    _CLOG="${WORK_DIR}/.logs"
    mkdir -p "${_CLOG}" 2>/dev/null || true
    log "Configuring companion runtimes in parallel (EXTRA_RUNTIMES='${EXTRA_RUNTIMES}')..."
    OLD_IFS="${IFS}"
    IFS=','
    for ext in ${EXTRA_RUNTIMES}; do
        IFS="${OLD_IFS}"
        ext_full=$(echo "${ext}" | tr -d '[:space:]')
        [ -z "${ext_full}" ] && continue
        # Per-component version syntax: name@version (e.g. python@3.12, bun@1.1)
        ext="${ext_full%%@*}"; ext_ver="${ext_full#*@}"
        [ "${ext_ver}" = "${ext_full}" ] && ext_ver="latest"
        ext=$(echo "${ext}" | tr '[:upper:]' '[:lower:]')
        if ! command -v "${ext}" >/dev/null 2>&1; then
            log "Installing companion runtime '${ext}' (version: ${ext_ver})..."
            (
                if /usr/local/bin/install-runtime.sh "${ext}" "${ext_ver}" "${WORK_DIR}/.runtimes" \
                        >>"${_CLOG}/runtime-install-${ext}.log" 2>&1; then
                    : >"${_CLOG}/.${ext}.install-ok"
                else
                    : >"${_CLOG}/.${ext}.install-failed"
                fi
            ) &
        fi
    done
    wait
    for marker in "${_CLOG}"/.*.install-failed; do
        [ -f "${marker}" ] || continue
        _name="$(basename "${marker}")"; _name="${_name#.}"; _name="${_name%.install-failed}"
        warn "Companion runtime '${_name}' FAILED -> see .logs/runtime-install-${_name}.log"
        rm -f "${marker}"
    done
    for marker in "${_CLOG}"/.*.install-ok; do
        [ -f "${marker}" ] && rm -f "${marker}"
    done
    IFS="${OLD_IFS}"
    build_isolated_environment
fi

if [ "${NODE_GYP_SUPPORT:-1}" = "1" ] && [ -f "package.json" ]; then
    if grep -qiE '("node-gyp"|"bindings"|"node-addon-api"|"canvas"|"sqlite3"|"bcrypt"|"sharp")' package.json 2>/dev/null; then
        if ! command -v python3 >/dev/null 2>&1; then
            log "Native C++/Python dependencies detected in package.json. Installing Python companion toolchain..."
            if [ -f /usr/local/bin/install-runtime.sh ]; then
                bash /usr/local/bin/install-runtime.sh "python" "latest" "${WORK_DIR}/.runtimes" >/dev/null 2>&1 || true
                build_isolated_environment
            fi
        fi
    fi
fi

# 7. Dependency Management & Package Installation
# -----------------------------------------------------------------------------
phase "Dependency Sync"
_DEP_FAILED=0
_DEP_LIFECYCLE_SKIPPED=0
if [ "${AUTO_INSTALL_DEPS}" = "1" ]; then
    mkdir -p "${WORK_DIR}/.logs" 2>/dev/null || true
    _dep_log="${WORK_DIR}/.logs/dependency-install.log"
    : > "${_dep_log}" 2>/dev/null || _dep_log="/dev/null"
    if [ -n "${CUSTOM_INSTALL_COMMAND}" ]; then
        log "Running CUSTOM_INSTALL_COMMAND: ${CUSTOM_INSTALL_COMMAND} (full output: .logs/dependency-install.log)"
        # Subshell guard: a custom command that calls `exit` must abort only
        # the install step, never the launcher itself.
        if ( eval "${CUSTOM_INSTALL_COMMAND}" ) >>"${_dep_log}" 2>&1; then
            ok "Custom install command finished"
        else
            _dep_rc=$?
            warn "CUSTOM_INSTALL_COMMAND failed (exit ${_dep_rc}) - see .logs/dependency-install.log"
            _egg_error_log "launcher" "CUSTOM_INSTALL_COMMAND failed (exit ${_dep_rc}): ${CUSTOM_INSTALL_COMMAND}"
            _DEP_FAILED=1
        fi
    else
        log "Synchronizing dependencies (AUTO_INSTALL_DEPS=1). Full output: .logs/dependency-install.log"
        # npm_try: run npm with the given args; on failure retry once with
        # lifecycle scripts disabled. A broken postinstall (common in app
        # repos referencing scripts that are not committed, or engines the
        # scripts do not support) must not leave the container without deps.
        npm_try() {
            if npm "$@" >>"${_dep_log}" 2>&1; then
                return 0
            fi
            if npm "$@" --ignore-scripts >>"${_dep_log}" 2>&1; then
                _DEP_LIFECYCLE_SKIPPED=1
                return 0
            fi
            return 1
        }
        _npm_install_fail() {
            warn "npm install failed - see .logs/dependency-install.log"
            _egg_error_log "launcher" "npm install failed - see .logs/dependency-install.log"
            _DEP_FAILED=1
        }
        case "${DETECTED_LANG}" in
            nodejs|javascript|js|typescript|ts)
                if [ -f "package.json" ]; then
                    if [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
                        log "Installing via pnpm..."
                        pnpm install --prefer-offline --frozen-lockfile >>"${_dep_log}" 2>&1 \
                            || pnpm install --prefer-offline >>"${_dep_log}" 2>&1 \
                            || { warn "pnpm install failed - see .logs/dependency-install.log"; _egg_error_log "launcher" "pnpm install failed - see .logs/dependency-install.log"; _DEP_FAILED=1; }
                    elif [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
                        log "Installing via yarn..."
                        yarn install --prefer-offline --frozen-lockfile >>"${_dep_log}" 2>&1 \
                            || yarn install --prefer-offline >>"${_dep_log}" 2>&1 \
                            || { warn "yarn install failed - see .logs/dependency-install.log"; _egg_error_log "launcher" "yarn install failed - see .logs/dependency-install.log"; _DEP_FAILED=1; }
                    elif [ -f "bun.lockb" ] && command -v bun >/dev/null 2>&1; then
                        log "Installing via bun..."
                        bun install --prefer-offline >>"${_dep_log}" 2>&1 \
                            || { warn "bun install failed - see .logs/dependency-install.log"; _egg_error_log "launcher" "bun install failed - see .logs/dependency-install.log"; _DEP_FAILED=1; }
                    elif [ -f "package-lock.json" ] && command -v npm >/dev/null 2>&1; then
                        # npm ci is significantly faster & fully reproducible when a
                        # lockfile exists; fall back to install on mismatched trees.
                        log "Installing via npm ci (lockfile detected)..."
                        { npm ci --no-audit --no-fund --prefer-offline \
                            || npm install --no-audit --no-fund --prefer-offline \
                            || npm ci --ignore-scripts --no-audit --no-fund --prefer-offline \
                            || npm install --ignore-scripts --no-audit --no-fund --prefer-offline; } >>"${_dep_log}" 2>&1 \
                            || { warn "npm install failed - see .logs/dependency-install.log"; _egg_error_log "launcher" "npm install/ci failed - see .logs/dependency-install.log"; _DEP_FAILED=1; }
                    else
                        log "Installing via npm..."
                        npm_try install --no-audit --no-fund --prefer-offline \
                            || { warn "npm install failed - see .logs/dependency-install.log"; _egg_error_log "launcher" "npm install failed - see .logs/dependency-install.log"; _DEP_FAILED=1; }
                    fi
                fi
                ;;

            python|py)
                if [ -f "requirements.txt" ]; then
                    log "Installing Python packages from requirements.txt..."
                    if command -v uv >/dev/null 2>&1; then
                        { uv pip install -r requirements.txt --system || pip3 install -r requirements.txt; } >>"${_dep_log}" 2>&1 \
                            || { warn "Python dependency install failed - see .logs/dependency-install.log"; _egg_error_log "launcher" "pip/uv install failed - see .logs/dependency-install.log"; _DEP_FAILED=1; }
                    else
                        { pip3 install -r requirements.txt --no-warn-script-location || pip install -r requirements.txt; } >>"${_dep_log}" 2>&1 \
                            || { warn "Python dependency install failed - see .logs/dependency-install.log"; _egg_error_log "launcher" "pip install failed - see .logs/dependency-install.log"; _DEP_FAILED=1; }
                    fi
                elif [ -f "pyproject.toml" ] && command -v poetry >/dev/null 2>&1; then
                    poetry install --no-interaction 2>/dev/null || true
                elif [ -f "Pipfile" ] && command -v pipenv >/dev/null 2>&1; then
                    pipenv install --deploy 2>/dev/null || pipenv install || true
                fi
                ;;

            bun)
                if [ -f "package.json" ]; then
                    log "Installing via bun..."
                    bun install --prefer-offline >>"${_dep_log}" 2>&1 \
                        || { warn "bun install failed - see .logs/dependency-install.log"; _egg_error_log "launcher" "bun install failed - see .logs/dependency-install.log"; _DEP_FAILED=1; }
                fi
                ;;

            golang|go)
                if [ -f "go.mod" ]; then
                    go mod download >>"${_dep_log}" 2>&1 \
                        || { warn "go mod download failed - see .logs/dependency-install.log"; _egg_error_log "launcher" "go mod download failed - see .logs/dependency-install.log"; _DEP_FAILED=1; }
                fi
                ;;

            rust|rs)
                if [ -f "Cargo.toml" ]; then
                    cargo fetch >>"${_dep_log}" 2>&1 \
                        || { warn "cargo fetch failed - see .logs/dependency-install.log"; _egg_error_log "launcher" "cargo fetch failed - see .logs/dependency-install.log"; _DEP_FAILED=1; }
                fi
                ;;

            php)
                if [ -f "composer.json" ] && command -v composer >/dev/null 2>&1; then
                    composer install --no-interaction --prefer-dist --optimize-autoloader 2>/dev/null || composer install || true
                fi
                ;;

            ruby)
                if [ -f "Gemfile" ] && command -v bundle >/dev/null 2>&1; then
                    bundle install 2>/dev/null || true
                fi
                ;;

            dotnet)
                if ls *.csproj 1>/dev/null 2>&1 || ls *.sln 1>/dev/null 2>&1; then
                    dotnet restore 2>/dev/null || true
                fi
                ;;
        esac
        # Honest end-of-step status: never claim success when installs failed,
        # and surface silently-skipped lifecycle scripts (postinstall guard).
        if [ "${_DEP_FAILED}" = "1" ]; then
            warn "Dependency installation reported errors - see .logs/dependency-install.log (continuing)"
        elif [ "${_DEP_LIFECYCLE_SKIPPED}" = "1" ]; then
            warn "Dependencies installed, but package lifecycle scripts (postinstall) were skipped after a failure - see .logs/dependency-install.log"
            ok "Dependencies ready (lifecycle scripts skipped)"
        else
            ok "Dependencies ready"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# 8. Build / Compilation Step
# -----------------------------------------------------------------------------
phase "Build Step"
if [ -n "${BUILD_COMMAND}" ]; then
    log "Executing BUILD_COMMAND: ${BUILD_COMMAND}..."
    if ! eval "${BUILD_COMMAND}"; then
        warn "BUILD_COMMAND failed (exit $?) - check output above for the compiler error."
        _egg_error_log "launcher" "BUILD_COMMAND failed: ${BUILD_COMMAND}"
    fi
    ok "Build step finished"
fi

if [ "${CLEAN_BUILD_CACHE}" = "1" ]; then
    rm -rf /tmp/.npm /tmp/.cargo /tmp/.cache /root/.cache ~/.npm/_cacache /tmp/pip* /tmp/*.tar.* /tmp/*.zip 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# 9. Entrypoint & Execution Dispatch
# -----------------------------------------------------------------------------
resolve_main_file() {
    if [ "${MAIN_FILE}" != "auto" ] && [ -n "${MAIN_FILE}" ]; then
        echo "${MAIN_FILE}"
        return
    fi

    case "${DETECTED_LANG}" in
        nodejs|javascript|js)
            for f in index.js app.js server.js main.js src/index.js src/app.js src/server.js src/main.js; do
                [ -f "$f" ] && echo "$f" && return
            done
            echo "index.js"
            ;;
        typescript|ts)
            for f in src/index.ts index.ts src/app.ts app.ts src/server.ts server.ts src/main.ts main.ts; do
                [ -f "$f" ] && echo "$f" && return
            done
            echo "src/index.ts"
            ;;
        bun)
            for f in index.ts index.js src/index.ts src/index.js app.ts server.ts main.ts; do
                [ -f "$f" ] && echo "$f" && return
            done
            echo "index.ts"
            ;;
        deno)
            for f in main.ts index.ts app.ts main.js index.js; do
                [ -f "$f" ] && echo "$f" && return
            done
            echo "main.ts"
            ;;
        python|py)
            for f in main.py app.py server.py bot.py src/main.py src/app.py manage.py; do
                [ -f "$f" ] && echo "$f" && return
            done
            echo "main.py"
            ;;
        golang|go)
            for f in main.go cmd/server/main.go cmd/main.go; do
                [ -f "$f" ] && echo "$f" && return
            done
            echo "main.go"
            ;;
        php)
            for f in index.php server.php app.php public/index.php; do
                [ -f "$f" ] && echo "$f" && return
            done
            echo "index.php"
            ;;
        ruby)
            for f in app.rb main.rb server.rb config.ru; do
                [ -f "$f" ] && echo "$f" && return
            done
            echo "app.rb"
            ;;
        static)
            for f in dist/index.html build/index.html public/index.html index.html; do
                [ -f "$f" ] && echo "$f" && return
            done
            echo "index.html"
            ;;
        bash|sh)
            for f in start.sh run.sh main.sh server.sh app.sh; do
                [ -f "$f" ] && echo "$f" && return
            done
            local sh_candidate
            sh_candidate=$(ls *.sh 2>/dev/null | grep -vE '^(entrypoint|run|install|install-runtime)\.sh$' | head -n1 || true)
            [ -n "${sh_candidate}" ] && echo "${sh_candidate}" && return
            echo "start.sh"
            ;;
        *)
            echo "index.js"
            ;;
    esac
}

RESOLVED_MAIN=$(resolve_main_file)

# Ensure fallback entrypoint exists so initial container run does not crash
if [ ! -f "${RESOLVED_MAIN}" ] && [ "${DETECTED_LANG}" != "static" ] && [ -z "${CUSTOM_COMMAND}" ]; then
    mkdir -p "$(dirname "${RESOLVED_MAIN}")" 2>/dev/null || true
    case "${DETECTED_LANG}" in
        nodejs|javascript|js)
            cat << 'EOF' > "${RESOLVED_MAIN}"
const http = require('http');
const port = process.env.SERVER_PORT || process.env.PORT || 8080;
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'online',
    message: 'Hello from PotenFYR Multi-Languages Runtime!',
    runtime: `Node.js ${process.version}`,
    timestamp: new Date().toISOString()
  }, null, 2));
});
server.listen(port, '0.0.0.0', () => {
  console.log(`[PotenFYR] Node.js server listening on port ${port}`);
});
EOF
            ok "Initialized entrypoint: ${RESOLVED_MAIN}"
            ;;

        typescript|ts)
            cat << 'EOF' > "${RESOLVED_MAIN}"
import http from 'http';
const port = Number(process.env.SERVER_PORT || process.env.PORT || 8080);
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    status: 'online',
    message: 'Hello from PotenFYR TypeScript Runtime!',
    runtime: `Node.js ${process.version}`,
    timestamp: new Date().toISOString()
  }, null, 2));
});
server.listen(port, '0.0.0.0', () => {
  console.log(`[PotenFYR] TypeScript server listening on port ${port}`);
});
EOF
            ok "Initialized entrypoint: ${RESOLVED_MAIN}"
            ;;

        bun)
            cat << 'EOF' > "${RESOLVED_MAIN}"
const port = Number(process.env.SERVER_PORT || process.env.PORT || 8080);
console.log(`[PotenFYR] Bun HTTP server listening on port ${port}`);
Bun.serve({
  port: port,
  fetch(req) {
    return new Response(JSON.stringify({
      status: "online",
      message: "Hello from PotenFYR Bun Runtime!",
      runtime: `Bun ${Bun.version}`,
      timestamp: new Date().toISOString()
    }, null, 2), {
      headers: { "Content-Type": "application/json" }
    });
  }
});
EOF
            ok "Initialized entrypoint: ${RESOLVED_MAIN}"
            ;;

        python|py)
            cat << 'EOF' > "${RESOLVED_MAIN}"
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
from datetime import datetime

PORT = int(os.environ.get("SERVER_PORT", os.environ.get("PORT", 8080)))

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            "status": "online",
            "message": "Hello from PotenFYR Python Runtime!",
            "runtime": f"Python {os.sys.version.split()[0]}",
            "timestamp": datetime.utcnow().isoformat()
        }, indent=2).encode())

print(f"[PotenFYR] Python HTTP server listening on port {PORT}")
HTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
EOF
            ok "Initialized entrypoint: ${RESOLVED_MAIN}"
            ;;

        golang|go)
            cat << 'EOF' > "${RESOLVED_MAIN}"
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"runtime"
	"time"
)

func main() {
	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = os.Getenv("PORT")
	}
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":    "online",
			"message":   "Hello from PotenFYR Go Runtime!",
			"runtime":   runtime.Version(),
			"timestamp": time.Now().Format(time.RFC3339),
		})
	})

	fmt.Printf("[PotenFYR] Go HTTP server listening on port %s\n", port)
	http.ListenAndServe("0.0.0.0:"+port, nil)
}
EOF
            [ -f "go.mod" ] || go mod init potenfyr-server 2>/dev/null || true
            ok "Initialized entrypoint: ${RESOLVED_MAIN}"
            ;;

        php)
            cat << 'EOF' > "${RESOLVED_MAIN}"
<?php
$port = getenv('SERVER_PORT') ?: (getenv('PORT') ?: 8080);
header('Content-Type: application/json');
echo json_encode([
    'status' => 'online',
    'message' => 'Hello from PotenFYR PHP Runtime!',
    'runtime' => 'PHP ' . PHP_VERSION,
    'timestamp' => gmdate('c')
], JSON_PRETTY_PRINT);
EOF
            ok "Initialized entrypoint: ${RESOLVED_MAIN}"
            ;;

        ruby)
            cat << 'EOF' > "${RESOLVED_MAIN}"
require 'webrick'
require 'json'
require 'time'

port = (ENV['SERVER_PORT'] || ENV['PORT'] || 8080).to_i
server = WEBrick::HTTPServer.new(:Port => port, :BindAddress => '0.0.0.0', :Logger => WEBrick::Log.new('/dev/null'), :AccessLog => [])

server.mount_proc '/' do |req, res|
  res['Content-Type'] = 'application/json'
  res.body = JSON.pretty_generate({
    status: 'online',
    message: 'Hello from PotenFYR Ruby Runtime!',
    runtime: "Ruby #{RUBY_VERSION}",
    timestamp: Time.now.utc.iso8601
  })
end

trap('INT') { server.shutdown }
puts "[PotenFYR] Ruby server listening on port #{port}"
server.start
EOF
            ok "Initialized entrypoint: ${RESOLVED_MAIN}"
            ;;
    esac
fi

# -----------------------------------------------------------------------------
# 9.1 Startup Value Sync + Runtime Details Card
# -----------------------------------------------------------------------------
# After detection, pin the concrete resolved values (language, engine, entry
# point, runtime version) into .multi-prog.conf whenever the corresponding
# startup variable still holds a placeholder (auto / latest / default / none /
# empty). On the NEXT boot the entrypoint prefers the pinned value over the
# placeholder, so what was decided on the first boot is what keeps running.
# Setting a variable to "auto-detect" clears its pin (handled by the
# entrypoint) and re-runs detection.
is_placeholder() {
    case "${1-}" in
        ""|auto|Auto|AUTO|latest|Latest|LATEST|default|Default|none|None) return 0 ;;
        *) return 1 ;;
    esac
}

sync_resolved_startup() {
    _pin_value() { # _pin_value KEY VALUE
        [ -n "${2:-}" ] || return 0
        save_conf "${1}" "${2}"
        log "Startup value pinned: ${1}=${2} (was a placeholder) - set it to 'auto-detect' in Startup to re-run detection."
    }
    # LANGUAGE: auto-detected language
    is_placeholder "${LANGUAGE:-}" && _pin_value "LANGUAGE" "${DETECTED_LANG}"
    # RUNTIME_VERSION: exact resolved version for "latest"
    if is_placeholder "${RUNTIME_VERSION:-}" && [ -n "${RUNTIME_VERSION_RESOLVED:-}" ]; then
        _pin_value "RUNTIME_VERSION" "${RUNTIME_VERSION_RESOLVED}"
    fi
    is_placeholder "${LANGUAGE_VERSION:-}" && [ -n "${RUNTIME_VERSION_RESOLVED:-}" ] && _pin_value "LANGUAGE_VERSION" "${RUNTIME_VERSION_RESOLVED}"
    # MAIN_FILE: resolved entry point
    if is_placeholder "${MAIN_FILE:-}" && [ -n "${RESOLVED_MAIN}" ] && [ -f "${RESOLVED_MAIN}" ]; then
        _pin_value "MAIN_FILE" "${RESOLVED_MAIN}"
    fi
    # RUNNER: effective engine when on auto
    if is_placeholder "${RUNNER:-}"; then
        val="$(_effective_runner)"
        [ -n "${val}" ] && _pin_value "RUNNER" "${val}"
    fi
    return 0
}

_effective_runner() {
    case "${DETECTED_LANG}" in
        nodejs|javascript|js)  echo "node" ;;
        typescript|ts)         if command -v tsx >/dev/null 2>&1; then echo "tsx"; elif command -v bun >/dev/null 2>&1; then echo "bun"; else echo "tsx"; fi ;;
        bun)                   echo "bun" ;;
        deno)                  echo "deno" ;;
        python|py)             echo "python3" ;;
        golang|go)             echo "go" ;;
        rust|rs)               echo "cargo" ;;
        php)                   echo "php" ;;
        ruby)                  echo "ruby" ;;
        java|jdk|openjdk)      echo "java" ;;
        dotnet|csharp|fsharp|vb) echo "dotnet" ;;
        *)                     echo "" ;;
    esac
}

print_card_row() {
    # 61-col card (1 leading space + 60 box): panel web consoles are only
    # ~62-64 cols wide (Feather Panel measured), so the old 68/69-col card
    # wrapped its right border onto the next line and garbled the whole box.
    # Values are truncated to the 35-col field so the border always lines up.
    local label="$1" value="$2" color="$3" max=35
    if [ "${#value}" -gt "$max" ]; then
        value="${value:0:$((max-3))}..."
    fi
    printf " ${C_DIM}│${C_RESET}  ${C_LIME}◆${C_RESET} ${C_BOLD}%-15s${C_RESET} : ${color}%-35s${C_RESET} ${C_DIM}│${C_RESET}\n" "${label}" "${value}"
}

print_runtime_card() {
    local runner_disp="${RUNNER:-auto}"
    if is_placeholder "${RUNNER:-}"; then
        local eff; eff="$(_effective_runner)"
        [ -n "${eff}" ] && runner_disp="auto → ${eff}"
    fi
    local ver_disp="${RUNTIME_VERSION_RESOLVED:-runtime default}"

    printf " ${C_DIM}┌──────────────────────────────────────────────────────────┐${C_RESET}\n"
    print_card_row "Target Language" "${DETECTED_LANG}" "${C_GREEN}"
    print_card_row "Runtime Version" "${ver_disp}" "${C_GREEN}"
    print_card_row "Runner / Engine" "${runner_disp}" "${C_CYAN}"
    print_card_row "Entry Point"     "${RESOLVED_MAIN} $([ -f "${RESOLVED_MAIN}" ] || echo '(stub created)')" "${C_YELLOW}"
    print_card_row "Host Platform"   "${PANEL_TYPE:-unknown}" "${C_BLUE}"
    print_card_row "Server UUID"     "${P_SERVER_UUID:-${SERVER_UUID:-${EMERALD_SRV_UUID:-not-provided}}}" "${C_DIM}"
    print_card_row "Memory Tuning"   "${AUTO_TUNE_INFO:-Default}" "${C_MAGENTA}"
    print_card_row "Port Allocation" "${SERVER_PORT} (0.0.0.0)" "${C_GREEN}"
    print_card_row "Egg Self-Update" "$([ "${AUTO_UPDATE_EGG:-1}" = "1" ] && echo Enabled || echo Disabled)" "${C_GREEN}"
    print_card_row "Process User"    "$(id -un 2>/dev/null || echo '?') (uid $(id -u 2>/dev/null || echo '?'))" "${C_BLUE}"
    print_card_row "Architecture"    "${ARCH:-$(uname -m 2>/dev/null)} ($(uname -s 2>/dev/null || echo linux))" "${C_CYAN}"
    print_card_row "Working Dir"     "${WORK_DIR}" "${C_DIM}"
    printf " ${C_DIM}└──────────────────────────────────────────────────────────┘${C_RESET}\n\n"
}

sync_resolved_startup
print_runtime_card

construct_run_cmd() {
    if [ -n "${CUSTOM_COMMAND}" ]; then
        echo "${CUSTOM_COMMAND}"
        return
    fi

    if [ "${DETECTED_LANG}" = "static" ]; then
        local static_dir="."
        [ -d "dist" ] && static_dir="dist"
        [ -d "build" ] && static_dir="build"
        [ -d "public" ] && static_dir="public"
        
        if command -v bun >/dev/null 2>&1; then
            echo "bun x serve -p ${SERVER_PORT} -s ${static_dir}"
        else
            echo "python3 -m http.server ${SERVER_PORT} --directory ${static_dir}"
        fi
        return
    fi

    case "${DETECTED_LANG}" in
        nodejs|javascript|js)
            local watch_flag=""
            [ "${DEV_MODE}" = "1" ] && watch_flag="--watch"
            
            if [ "${RUNNER}" = "npm" ]; then
                echo "npm start ${EXTRA_ARGS}"
            elif [ "${RUNNER}" = "yarn" ]; then
                echo "yarn start ${EXTRA_ARGS}"
            elif [ "${RUNNER}" = "pnpm" ]; then
                echo "pnpm start ${EXTRA_ARGS}"
            elif [ "${RUNNER}" = "pm2" ]; then
                echo "pm2-runtime ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            elif [ "${RUNNER}" = "nodemon" ] || [ "${DEV_MODE}" = "1" ]; then
                echo "node ${watch_flag} ${EXTRA_ARGS} ${RESOLVED_MAIN}"
            else
                echo "node ${EXTRA_ARGS} ${RESOLVED_MAIN}"
            fi
            ;;

        typescript|ts)
            if [ "${RUNNER}" = "bun" ]; then
                local bun_watch=""
                [ "${DEV_MODE}" = "1" ] && bun_watch="--watch"
                echo "bun run ${bun_watch} ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            elif [ "${RUNNER}" = "deno" ]; then
                local deno_watch=""
                [ "${DEV_MODE}" = "1" ] && deno_watch="--watch"
                echo "deno run -A ${deno_watch} ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            elif [ "${RUNNER}" = "tsx" ]; then
                local tsx_watch=""
                [ "${DEV_MODE}" = "1" ] && tsx_watch="watch"
                if command -v tsx >/dev/null 2>&1; then
                    echo "tsx ${tsx_watch} ${RESOLVED_MAIN} ${EXTRA_ARGS}"
                else
                    echo "npx -y tsx ${tsx_watch} ${RESOLVED_MAIN} ${EXTRA_ARGS}"
                fi
            elif [ "${RUNNER}" = "ts-node" ]; then
                if command -v ts-node >/dev/null 2>&1; then
                    echo "ts-node ${RESOLVED_MAIN} ${EXTRA_ARGS}"
                else
                    echo "npx -y ts-node ${RESOLVED_MAIN} ${EXTRA_ARGS}"
                fi
            elif [ "${RUNNER}" = "tsc" ]; then
                echo "tsc && node dist/index.js ${EXTRA_ARGS}"
            else
                if command -v bun >/dev/null 2>&1; then
                    local bun_watch=""
                    [ "${DEV_MODE}" = "1" ] && bun_watch="--watch"
                    echo "bun run ${bun_watch} ${RESOLVED_MAIN} ${EXTRA_ARGS}"
                elif command -v tsx >/dev/null 2>&1; then
                    local tsx_watch=""
                    [ "${DEV_MODE}" = "1" ] && tsx_watch="watch"
                    echo "tsx ${tsx_watch} ${RESOLVED_MAIN} ${EXTRA_ARGS}"
                elif command -v ts-node >/dev/null 2>&1; then
                    echo "ts-node ${RESOLVED_MAIN} ${EXTRA_ARGS}"
                else
                    echo "npx -y tsx ${RESOLVED_MAIN} ${EXTRA_ARGS}"
                fi
            fi
            ;;

        bun)
            local bun_watch=""
            [ "${DEV_MODE}" = "1" ] && bun_watch="--watch"
            echo "bun run ${bun_watch} ${EXTRA_ARGS} ${RESOLVED_MAIN}"
            ;;

        deno)
            local deno_watch=""
            [ "${DEV_MODE}" = "1" ] && deno_watch="--watch"
            echo "deno run -A --unstable ${deno_watch} ${EXTRA_ARGS} ${RESOLVED_MAIN}"
            ;;

        python|py)
            if [ "${RUNNER}" = "uvicorn" ]; then
                local uvi_reload=""
                [ "${DEV_MODE}" = "1" ] && uvi_reload="--reload"
                MOD_NAME=$(basename "${RESOLVED_MAIN}" .py)
                echo "uvicorn ${MOD_NAME}:app --host 0.0.0.0 --port ${SERVER_PORT} ${uvi_reload} ${EXTRA_ARGS}"
            elif [ "${RUNNER}" = "gunicorn" ]; then
                MOD_NAME=$(basename "${RESOLVED_MAIN}" .py)
                echo "gunicorn -b 0.0.0.0:${SERVER_PORT} ${MOD_NAME}:app ${EXTRA_ARGS}"
            elif [ "${RUNNER}" = "poetry" ]; then
                echo "poetry run python ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            elif [ "${RUNNER}" = "pipenv" ]; then
                echo "pipenv run python ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            else
                echo "python3 ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        golang|go)
            if [ -f "./server" ]; then
                echo "./server ${EXTRA_ARGS}"
            elif [ -f "${RESOLVED_MAIN}" ]; then
                echo "go run ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            else
                echo "go run . ${EXTRA_ARGS}"
            fi
            ;;

        rust|rs)
            if [ -f "./target/release/server" ]; then
                echo "./target/release/server ${EXTRA_ARGS}"
            elif [ -f "Cargo.toml" ]; then
                echo "cargo run --release ${EXTRA_ARGS}"
            else
                echo "rustc ${RESOLVED_MAIN} -o server && ./server ${EXTRA_ARGS}"
            fi
            ;;

        java|jdk|openjdk)
            local jvm_flags="${JAVA_AUTO_MEM_FLAGS} ${JAVA_AUTO_GC} ${EXTRA_ARGS}"
            JAR_FOUND=$(ls *.jar 2>/dev/null | head -n1 || true)
            if [ -n "${JAR_FOUND}" ]; then
                echo "java ${jvm_flags} -jar ${JAR_FOUND}"
            elif [ -f "pom.xml" ]; then
                [ -x "./mvnw" ] && echo "./mvnw spring-boot:run" || echo "mvn spring-boot:run"
            elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
                [ -x "./gradlew" ] && echo "./gradlew bootRun" || echo "gradle bootRun"
            elif [ -f "Main.java" ]; then
                echo "java ${jvm_flags} Main.java"
            else
                echo "java ${jvm_flags} -jar ${MAIN_FILE}"
            fi
            ;;

        c-cpp|cpp|c)
            if [ -f "Makefile" ]; then
                echo "make run ${EXTRA_ARGS}"
            elif [ -f "./server" ]; then
                echo "./server ${EXTRA_ARGS}"
            elif [ -f "./a.out" ]; then
                echo "./a.out ${EXTRA_ARGS}"
            elif ls *.cpp 1>/dev/null 2>&1; then
                CPP_FILE=$(ls *.cpp | head -n1)
                echo "g++ -O3 ${CPP_FILE} -o server && ./server ${EXTRA_ARGS}"
            elif ls *.c 1>/dev/null 2>&1; then
                C_FILE=$(ls *.c | head -n1)
                echo "gcc -O3 ${C_FILE} -o server && ./server ${EXTRA_ARGS}"
            else
                echo "./server ${EXTRA_ARGS}"
            fi
            ;;

        php)
            if [ "${RUNNER}" = "artisan" ]; then
                echo "php artisan serve --host=0.0.0.0 --port=${SERVER_PORT} ${EXTRA_ARGS}"
            else
                echo "php -S 0.0.0.0:${SERVER_PORT} ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        dotnet|csharp|fsharp|vb)
            echo "dotnet run ${EXTRA_ARGS}"
            ;;

        ruby)
            if [ -f "Gemfile" ] && command -v bundle >/dev/null 2>&1; then
                echo "bundle exec ruby ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            else
                echo "ruby ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        zig)
            if [ -f "build.zig" ]; then
                echo "zig build run ${EXTRA_ARGS}"
            else
                echo "zig run ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        swift)
            if [ -f "Package.swift" ]; then
                echo "swift run ${EXTRA_ARGS}"
            else
                echo "swift ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        dart)
            echo "dart run ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            ;;

        lua)
            if command -v luajit >/dev/null 2>&1; then
                echo "luajit ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            else
                echo "lua ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        elixir)
            if [ -f "mix.exs" ]; then
                echo "mix run --no-halt ${EXTRA_ARGS}"
            else
                echo "elixir ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        erlang)
            if [ -f "rebar.config" ]; then
                echo "rebar3 shell"
            else
                echo "escript ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        haskell)
            if ls *.cabal >/dev/null 2>&1 || [ -f "stack.yaml" ]; then
                echo "cabal run ${EXTRA_ARGS}"
            else
                echo "runghc ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        perl)
            echo "perl ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            ;;

        r)
            echo "Rscript ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            ;;

        julia)
            echo "julia ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            ;;

        clojure)
            if [ -f "project.clj" ]; then
                echo "lein run ${EXTRA_ARGS}"
            else
                echo "clojure -M ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        groovy)
            echo "groovy ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            ;;

        crystal)
            echo "crystal run ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            ;;

        nim)
            echo "nim r -d:release ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            ;;

        ocaml)
            if [ -f "dune-project" ]; then
                echo "dune exec ./main.exe ${EXTRA_ARGS}"
            else
                echo "ocaml ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            fi
            ;;

        fortran)
            echo "gfortran ${RESOLVED_MAIN} -o app && ./app ${EXTRA_ARGS}"
            ;;

        pascal)
            echo "fpc ${RESOLVED_MAIN} && ./$(basename "${RESOLVED_MAIN}" .pas) ${EXTRA_ARGS}"
            ;;

        cobol)
            echo "cobc -x -free ${RESOLVED_MAIN} -o cobapp && ./cobapp ${EXTRA_ARGS}"
            ;;

        v)
            echo "v run ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            ;;

        odin)
            echo "odin run . ${EXTRA_ARGS}"
            ;;

        gleam)
            echo "gleam run ${EXTRA_ARGS}"
            ;;

        bash|sh)
            if [ -n "${RESOLVED_MAIN}" ] && [ -f "${RESOLVED_MAIN}" ]; then
                echo "bash ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            else
                echo "node index.js ${EXTRA_ARGS}"
            fi
            ;;

        powershell|pwsh)
            echo "pwsh ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            ;;

        *)
            echo "node ${RESOLVED_MAIN} ${EXTRA_ARGS}"
            ;;
    esac
}

RUN_CMD=$(construct_run_cmd)

# -----------------------------------------------------------------------------
# 10. Execution Loop & Process Handling
# -----------------------------------------------------------------------------
phase "Application Launch"
print_crash_diagnostics() {
    local exit_code="$1"
    [ "${exit_code}" -eq 0 ] && return 0

    _egg_error_log "launcher" "application process crashed with exit code ${exit_code} (lang=${DETECTED_LANG}, cmd=${RUN_CMD})"

    # 61-col card, same geometry as the runtime details card (see
    # print_card_row): panel web consoles are ~62-64 cols, the old 76-col
    # card wrapped and garbled. Plain ASCII header (emoji are double-width
    # and shift the right border on most console fonts).
    printf "\n ${C_RED}${C_BOLD}┌──────────────────────────────────────────────────────────┐${C_RESET}\n"
    printf " ${C_RED}${C_BOLD}│ PROCESS CRASH & DIAGNOSTIC REPORT                        │${C_RESET}\n"
    printf " ${C_RED}${C_BOLD}├──────────────────────────────────────────────────────────┤${C_RESET}\n"

    # 1. Exit status
    printf " ${C_DIM}│${C_RESET}  ${C_RED}◆${C_RESET} ${C_BOLD}%-15s${C_RESET} : ${C_RED}%-35s${C_RESET} ${C_DIM}│${C_RESET}\n" "Crash Status" "Exit Code ${exit_code}"

    # 2. Active Runtime
    local runtime_ver="Unknown"
    case "${DETECTED_LANG}" in
        nodejs|javascript|js) runtime_ver=$(node -v 2>/dev/null || echo "Node.js (not found)") ;;
        bun)                  runtime_ver=$(bun -v 2>/dev/null && echo "Bun $(bun -v)" || echo "Bun (not found)") ;;
        typescript|ts)        runtime_ver=$(tsx -v 2>/dev/null || bun -v 2>/dev/null || node -v 2>/dev/null || echo "TypeScript (not found)") ;;
        python|py)            runtime_ver=$(python3 --version 2>/dev/null || echo "Python (not found)") ;;
        golang|go)            runtime_ver=$(go version 2>/dev/null || echo "Go (not found)") ;;
        rust|rs)              runtime_ver=$(rustc --version 2>/dev/null || echo "Rust (not found)") ;;
        java)                 runtime_ver=$(java -version 2>&1 | head -n1 || echo "Java (not found)") ;;
        php)                  runtime_ver=$(php -v 2>/dev/null | head -n1 || echo "PHP (not found)") ;;
        ruby)                 runtime_ver=$(ruby -v 2>/dev/null || echo "Ruby (not found)") ;;
        dotnet)               runtime_ver=$(dotnet --version 2>/dev/null || echo ".NET (not found)") ;;
        *)                    runtime_ver="${DETECTED_LANG}" ;;
    esac
    [ "${#runtime_ver}" -gt 35 ] && runtime_ver="${runtime_ver:0:32}..."
    printf " ${C_DIM}│${C_RESET}  ${C_CYAN}◆${C_RESET} ${C_BOLD}%-15s${C_RESET} : ${C_CYAN}%-35s${C_RESET} ${C_DIM}│${C_RESET}\n" "Active Runtime" "${runtime_ver}"

    # 3. Memory Diagnostics
    local mem_info="N/A"
    if [ -f "/sys/fs/cgroup/memory/memory.usage_in_bytes" ]; then
        local used_bytes
        used_bytes=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || echo "0")
        local used_mb=$((used_bytes / 1024 / 1024))
        mem_info="${used_mb}MB Used"
        if [ -f "/sys/fs/cgroup/memory/memory.limit_in_bytes" ]; then
            local limit_bytes
            limit_bytes=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "0")
            local limit_mb=$((limit_bytes / 1024 / 1024))
            [ "${limit_mb}" -lt 999999 ] && mem_info="${used_mb}MB / ${limit_mb}MB Limit"
        fi
    elif [ -f "/sys/fs/cgroup/memory.current" ]; then
        local used_bytes
        used_bytes=$(cat /sys/fs/cgroup/memory.current 2>/dev/null || echo "0")
        local used_mb=$((used_bytes / 1024 / 1024))
        mem_info="${used_mb}MB Used"
        if [ -f "/sys/fs/cgroup/memory.max" ]; then
            local max_val
            max_val=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "max")
            if [ "${max_val}" != "max" ]; then
                local limit_mb=$((max_val / 1024 / 1024))
                mem_info="${used_mb}MB / ${limit_mb}MB Limit"
            fi
        fi
    fi
    printf " ${C_DIM}│${C_RESET}  ${C_MAGENTA}◆${C_RESET} ${C_BOLD}%-15s${C_RESET} : ${C_MAGENTA}%-35s${C_RESET} ${C_DIM}│${C_RESET}\n" "Memory Consumed" "${mem_info}"

    # 4. Disk Usage
    local disk_info
    disk_info=$(df -h "${WORK_DIR}" 2>/dev/null | tail -n1 | awk '{print $4 " available (" $5 " used)"}' || echo "N/A")
    printf " ${C_DIM}│${C_RESET}  ${C_YELLOW}◆${C_RESET} ${C_BOLD}%-15s${C_RESET} : ${C_YELLOW}%-35s${C_RESET} ${C_DIM}│${C_RESET}\n" "Disk Space" "${disk_info:0:35}"

    # 5. Suggested actions
    printf " ${C_DIM}│${C_RESET}  ${C_GREEN}◆${C_RESET} ${C_BOLD}%-15s${C_RESET} : ${C_WHITE}%-35s${C_RESET} ${C_DIM}│${C_RESET}\n" "Recommendation" "Check syntax, entry point, deps"
    printf " ${C_RED}${C_BOLD}└──────────────────────────────────────────────────────────┘${C_RESET}\n\n"

    # 6. Recent application output (before the crash) for quick diagnosis
    local _clog="${WORK_DIR}/.logs/console.log"
    if [ -f "${_clog}" ]; then
        printf "${C_DIM}  ▼ last 12 console lines before the crash (.logs/console.log):%b\n" "${C_RESET}"
        tail -n 12 "${_clog}" 2>/dev/null | sed 's/^/  | /'
        printf "\n"
    fi
    log "Full error journal: .logs/launcher-errors.log · console mirror: .logs/console.log"

    log "Holding 5-second diagnostic buffer to ensure complete console log stream..."
    sleep 5
}

while [ "${RUN_LOOP}" -eq 1 ]; do
    # Multi-process containers: kill any strays left over from a previous
    # run/crash (pm2 daemons, detached workers) so ports are free and no stale
    # process keeps serving between restarts.
    sweep_stray_processes quick
    log "Starting application process..."
    printf "%b>>> %s%b\n\n" "${C_GREEN}${C_BOLD}" "${RUN_CMD}" "${C_RESET}"

    eval "${RUN_CMD}" &
    CHILD_PID=$!

    # --- Health Check (first boot only) --------------------------------------
    # HEALTH_CHECK_PATH=/healthz probes http://127.0.0.1:$SERVER_PORT$PATH until
    # it answers. HEALTH_STRICT=1 turns a failed probe into a non-zero exit.
    if [ "${HEALTH_CHECK_DONE:-0}" != "1" ] && [ -n "${HEALTH_CHECK_PATH:-}" ]; then
        export HEALTH_CHECK_DONE=1
        (
            local_probe() {
                local url="http://127.0.0.1:${SERVER_PORT}${HEALTH_CHECK_PATH}"
                local waited=0 timeout="${HEALTH_TIMEOUT:-60}"
                while [ "${waited}" -lt "${timeout}" ]; do
                    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${url}" 2>/dev/null || echo 000)
                    case "${code}" in
                        2??|3??)
                            ok "Health check PASS (${url} -> HTTP ${code})"
                            return 0 ;;
                    esac
                    sleep 2; waited=$((waited+2))
                done
                warn "Health check FAILED after ${timeout}s (${url}, last code ${code})."
                _egg_error_log "launcher" "health check failed: ${url} (last HTTP code ${code}, waited ${timeout}s) - app may not listen on SERVER_PORT"
                [ "${HEALTH_STRICT:-0}" = "1" ] && exit 1
                return 0
            }
            local_probe
        ) &
        HEALTH_PID=$!
    fi

    if [ -n "${CHILD_PID:-}" ] && [ "${CHILD_PID}" -gt 1 ]; then
            wait "${CHILD_PID}" 2>/dev/null
            EXIT_CODE=$?
        else
            EXIT_CODE=0
        fi
    # Reap health-check probe before deciding on restart/exit
    if [ -n "${HEALTH_PID:-}" ] && [ "${HEALTH_PID}" -gt 1 ] 2>/dev/null; then
        terminate_process_tree "${HEALTH_PID}" 2
        HEALTH_PID=""
    fi
    CHILD_PID=0
    
    if [ "${RUN_LOOP}" -eq 0 ]; then
        break
    fi

    if [ "${AUTO_RESTART}" = "1" ]; then
        warn "Process exited with code ${EXIT_CODE}. AUTO_RESTART is enabled."
        print_crash_diagnostics "${EXIT_CODE}"
        log "Restarting in ${RESTART_DELAY} seconds... (Press Ctrl+C to abort)"
        local_delay="${RESTART_DELAY:-3}"
        while [ "${local_delay}" -gt 0 ] && [ "${RUN_LOOP}" -eq 1 ]; do
            sleep 1 &
            SLEEP_PID=$!
            wait "${SLEEP_PID}" 2>/dev/null || true
            SLEEP_PID=0
            local_delay=$((local_delay - 1))
        done
        [ "${RUN_LOOP}" -eq 0 ] && break
    else
        log "Process exited with code ${EXIT_CODE}."
        if [ "${EXIT_CODE}" -ne 0 ]; then
            print_crash_diagnostics "${EXIT_CODE}"
        fi
        if [ -n "${POST_RUN_COMMAND}" ]; then
            eval "${POST_RUN_COMMAND}" || true
        fi
        exit "${EXIT_CODE}"
    fi
done
