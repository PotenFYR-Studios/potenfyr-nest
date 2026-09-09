#!/bin/bash
# =============================================================================
#  Multi-Language Eggs - Runtime Version Resolver & Validator
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Prog-Language-Eggs)
#
#  Resolves user-facing version requests into concrete versions/toolchains,
#  using LIVE upstream feeds (no hardcoded pins). Validates inputs BEFORE any
#  download starts so bad version strings fail fast with clear guidance.
#
#  Usage:
#    resolve-version.sh <language> <request>
#    resolve-version.sh nodejs 22          -> newest 22.x.y        (feed lookup)
#    resolve-version.sh nodejs latest      -> newest current line
#    resolve-version.sh nodejs lts         -> newest LTS
#    resolve-version.sh nodejs nightly     -> newest nightly build
#    resolve-version.sh rust nightly       -> "nightly"            (native token)
#    resolve-version.sh python 3.12        -> 3.12.x               (feed lookup)
#    resolve-version.sh go invalid!!       -> FAILS with valid examples
#
#  Supported request forms:
#    Keywords : latest stable lts current default alpha beta rc pre preview
#               nightly dev tip edge canary
#    Versions : 22 | 22.1 | 22.1.4   (optionally "v"-prefixed: v22.1.4)
#
#  Output: exactly ONE line on stdout = resolved version/token.
#          All diagnostics go to stderr AND $WORK_DIR/.logs/version-resolver.log
#  Exit codes: 0 ok | 64 invalid request | 65 feed/unresolved | 66 unsupported
# =============================================================================

set -uo pipefail

C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'

LOG_DIR="${WORK_DIR:-$PWD}/.logs"; mkdir -p "${LOG_DIR}" 2>/dev/null || LOG_DIR="/tmp/potenfyr-logs"
LOG_FILE="${LOG_DIR}/version-resolver.log"

_vlog() { printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >>"${LOG_FILE}" 2>/dev/null || true; }
v_info() { printf "%b %s\n" "${C_BLUE}${C_BOLD}[PotenFYR][ver]${C_RESET}" "$2" >&2; _vlog "$1" "$2"; }
v_warn() { printf "%b %s\n" "${C_YELLOW}${C_BOLD}[PotenFYR][ver][!]${C_RESET}" "$2" >&2; _vlog "WARN" "$2"; }

LANG_IN="${1:-}"
REQ="${2:-}"

fail_invalid() { # fail_invalid <detail>
    printf "\n" >&2
    printf "${C_RED}${C_BOLD}[PotenFYR][ver][X] Invalid version request: '%s'${C_RESET}\n" "${REQ}" >&2
    printf "${C_RED}  %s${C_RESET}\n" "$1" >&2
    printf "${C_YELLOW}  Accepted forms:${C_RESET}\n" >&2
    printf "${C_YELLOW}    keywords : latest, stable, lts, alpha, beta, rc, preview, nightly${C_RESET}\n" >&2
    printf "${C_YELLOW}    versions : 22 | 22.1 | 22.1.4 | v22.1.4${C_RESET}\n" >&2
    printf "${C_DIM}  Log: ${LOG_FILE}${C_RESET}\n" >&2
    _vlog "FAIL" "invalid request '${REQ}' for ${LANG_IN}: $1"
    exit 64
}

fail_unresolved() {
    printf "\n" >&2
    printf "${C_RED}${C_BOLD}[PotenFYR][ver][X] Could not resolve '${REQ}' for ${LANG_IN}: %s${C_RESET}\n" "$1" >&2
    printf "${C_DIM}  Upstream feed may be down or the series retired. Check ${LOG_FILE}${C_RESET}\n" >&2
    _vlog "FAIL" "unresolved '${REQ}' for ${LANG_IN}: $1"
    exit 65
}

[ -z "${LANG_IN}" ] && { printf "usage: resolve-version.sh <language> <request>\n" >&2; exit 64; }
[ -z "${REQ}" ] && REQ="latest"

_vlog "INFO" "resolve start: language=${LANG_IN} request='${REQ}' arch=$(uname -m)"

# --- Security-first validation: strict allowlist before anything else --------
validate_request() {
    local r="${REQ#v}"
    case "${r}" in
        latest|stable|lts|current|default|alpha|beta|rc|pre|preview|nightly|dev|tip|edge|canary|master)
            return 0 ;;
        *)
            if [[ "${r}" =~ ^[0-9]+(\.[0-9]+){0,2}(-[A-Za-z0-9.+]+)?$ ]]; then return 0; fi
            fail_invalid "not a keyword and not a numeric version (x | x.y | x.y.z)."
            ;;
    esac
}
validate_request

# --- TTL result cache: identical requests within the TTL skip live feeds ------
CACHE_ROOT="${WORK_DIR:-${PWD}}/.cache/version-resolver"
CACHE_TTL="${RESOLVER_CACHE_TTL:-21600}"   # 6h default; 0 disables caching
_cache_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }
CACHE_FILE="${CACHE_ROOT}/$( _cache_key "${LANG_NORM:-${LANG_IN}}__${REQ}" )"
cache_lookup() {
    [ "${CACHE_TTL}" -gt 0 ] 2>/dev/null || return 1
    [ -f "${CACHE_FILE}" ] || return 1
    local age now mtime
    now=$(date +%s); mtime=$(stat -c %Y "${CACHE_FILE}" 2>/dev/null || echo 0)
    age=$(( now - mtime ))
    [ "${age}" -lt "${CACHE_TTL}" ] || return 1
    local v; v=$(cat "${CACHE_FILE}" 2>/dev/null)
    [ -n "${v}" ] || return 1
    v_info "RESOLVE" "${LANG_IN}: '${REQ}' -> ${v} (cached, ${age}s old)"
    printf '%s\n' "${v}"
    exit 0
}
cache_store() {
    [ "${CACHE_TTL}" -gt 0 ] 2>/dev/null || return 0
    mkdir -p "${CACHE_ROOT}" 2>/dev/null || true
    printf '%s\n' "$1" > "${CACHE_FILE}" 2>/dev/null || true
}
# NOTE: LANG_NORM is defined later in the dispatch section; cache uses it there.

is_kw() { case "$1" in latest|stable|lts|current|default) return 0 ;; *) return 1 ;; esac; }
is_pre() { case "$1" in alpha|beta|rc|pre|preview) return 0 ;; *) return 1 ;; esac; }

# --- Feed helpers -------------------------------------------------------------
fetch_json() { # fetch_json <url> <dest>
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 \
        -A "ProgLanguageEggs/1.0 (PotenFYR; version-resolver)" -o "$2" "$1" 2>>"${LOG_FILE}"
}

norm_lang() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]._-')" in
        node|nodejs|nodejsjavascript|javascript|js|ts|typescript|tsx|tsnode) echo "nodejs" ;;
        bun)      echo "bun" ;;
        deno)     echo "deno" ;;
        py|python|python3) echo "python" ;;
        go|golang|golanggo) echo "go" ;;
        rs|rust|rustc|cargo) echo "rust" ;;
        java|jdk|openjdk|temurin) echo "java" ;;
        dotnet|net|csharp|fsharp|vb) echo "dotnet" ;;
        zig)      echo "zig" ;;
        dart)     echo "dart" ;;
        *)        echo "$1" ;;   # passthrough families (validated, pinned channels)
    esac
}

strip_v() { echo "${1#v}"; }
strip_bun() { echo "$1" | sed -E 's/^bun-v?//'; }

# =============================================================================
# Per-language resolvers (live feeds only)
# =============================================================================

resolve_nodejs() {
    local idx="/tmp/potenfyr-node-index.json"
    if [ "${REQ}" = "nightly" ] || [ "${REQ}" = "dev" ]; then
        fetch_json "https://nodejs.org/download/nightly/index.json" "${idx}" || fail_unresolved "nightly feed unreachable"
        jq_get() { jq -r "$1 // empty" "${idx}" 2>>"${LOG_FILE}" || true; }
        local v; v=$(jq_get '[.[0].version]')
        [ -z "${v}" ] && fail_unresolved "nightly feed returned no versions"
        echo "${v}"; return 0
    fi
    fetch_json "https://nodejs.org/dist/index.json" "${idx}" || fail_unresolved "nodejs.org dist feed unreachable"
    local q
    case "${REQ}" in
        latest)  q='.[0].version' ;;
        stable)  q='[.[] | select(.lts != false)][0].version' ;;       # newest LTS = "stable" choice
        lts)     q='[.[] | select(.lts != false)][0].version' ;;
        current) q='.[0].version' ;;
        *)
            local r="${REQ#v}"
            if [[ "${r}" =~ ^[0-9]+$ ]]; then
                q="[.[] | select(.version | startswith(\"v${r}.\"))][0].version"
            elif [[ "${r}" =~ ^[0-9]+\.[0-9]+$ ]]; then
                q="[.[] | select(.version | startswith(\"v${r}.\"))][0].version"
            else
                q="[.[] | select(.version == \"v${r}\")][0].version"
            fi
            ;;
    esac
    local v
    v=$(jq -r "${q} // empty" "${idx}" 2>>"${LOG_FILE}")
    [ -z "${v}" ] && fail_unresolved "no Node.js release matches '${REQ}'. Try: 18, 20, 20.11, 22, latest, lts"
    echo "${v}"
}

resolve_bun() {
    local rel="/tmp/potenfyr-bun-rel.json"
    if fetch_json "https://api.github.com/repos/oven-sh/bun/releases/latest" "${rel}"; then
        local tag
        tag=$(jq -r '.tag_name // empty' "${rel}" 2>>"${LOG_FILE}")
        case "${REQ}" in
            latest|stable|current|default|lts) [ -n "${tag}" ] && { echo "$(strip_bun "${tag}")"; return 0; } ;;
        esac
    fi
    if is_pre "${REQ}" || [ "${REQ}" = "nightly" ] || [ "${REQ}" = "canary" ]; then
        # Canary/pre-release line (best effort)
        local list="/tmp/potenfyr-bun-list.json"
        fetch_json "https://api.github.com/repos/oven-sh/bun/releases?per_page=30" "${list}" || true
        local tag
        tag=$(jq -r '[.[] | select(.prerelease == true)][0].tag_name // empty' "${list}" 2>>"${LOG_FILE}")
        [ -z "${tag}" ] && tag=$(jq -r '[.[] | select(.tag_name | test("canary"))][0].tag_name // empty' "${list}" 2>>"${LOG_FILE}")
        if [ -n "${tag}" ]; then v_info "RESOLVE" "Bun pre-release channel selected: ${tag}"; echo "$(strip_bun "${tag}")"; return 0; fi
        v_info "WARN" "No Bun pre-release available; falling back to latest stable."
        tag=$(jq -r '.tag_name // empty' "${rel}" 2>>"${LOG_FILE}")
        [ -n "${tag}" ] && { echo "$(strip_bun "${tag}")"; return 0; }
        fail_unresolved "GitHub releases feed unavailable"
    fi
    # Numeric requests pass through (installer verifies existence against feed)
    echo "${REQ#v}"
}

resolve_deno() {
    local list="/tmp/potenfyr-deno-list.json"
    fetch_json "https://api.github.com/repos/denoland/deno/releases?per_page=40" "${list}" || fail_unresolved "Deno GitHub feed unreachable"
    case "${REQ}" in
        latest|stable|current|default|lts)
            jq -r '[.[] | select(.prerelease == false)][0].tag_name // empty' "${list}" 2>>"${LOG_FILE}" | sed 's/^v//'
            return 0 ;;
        alpha|beta|rc|pre|preview|nightly|canary|edge|dev)
            local t
            t=$(jq -r '[.[] | select(.prerelease == true)][0].tag_name // empty' "${list}" 2>>"${LOG_FILE}")
            if [ -n "${t}" ]; then echo "${t#v}"; return 0; fi
            v_info "WARN" "No Deno pre-release published right now; using latest stable."
            jq -r '[.[] | select(.prerelease == false)][0].tag_name // empty' "${list}" 2>>"${LOG_FILE}" | sed 's/^v//'
            return 0 ;;
    esac
    local r="${REQ#v}"
    [[ "${r}" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail_unresolved "unmatched Deno request"
    local hit
    hit=$(jq -r --arg p "v${r}" '[.[].tag_name | select(startswith($p))][0] // empty' "${list}" 2>>"${LOG_FILE}")
    [ -z "${hit}" ] && fail_unresolved "no Deno tag matches '${REQ}'"
    echo "${hit#v}"
}

resolve_python() {
    local eol="/tmp/potenfyr-python-eol.json"
    fetch_json "https://endoflife.date/api/python.json" "${eol}" || fail_unresolved "endoflife.date python feed unreachable"
    case "${REQ}" in
        latest|stable|current|default)
            jq -r '.[0].latest // empty' "${eol}" 2>>"${LOG_FILE}" ;;
        lts)
            v_info "INFO" "Python has no formal LTS brand; selecting newest mature 3.x."
            jq -r '.[0].latest // empty' "${eol}" 2>>"${LOG_FILE}" ;;
        alpha|beta|rc|pre|preview|nightly|dev)
            v_info "WARN" "Pre-release Python builds are not curated here; selecting newest stable."
            jq -r '.[0].latest // empty' "${eol}" 2>>"${LOG_FILE}" ;;
        *)
            local r="${REQ#v}"
            if [[ "${r}" =~ ^[0-9]+\.[0-9]+$ ]]; then
                jq -r --arg c "${r}" '.[] | select(.cycle == $c) | .latest // empty' "${eol}" 2>>"${LOG_FILE}"
            elif [[ "${r}" =~ ^[0-9]+$ ]]; then
                jq -r --arg c "${r}" '[.[] | select(.cycle | startswith($c + "."))][0].latest // empty' "${eol}" 2>>"${LOG_FILE}"
            else
                jq -r --arg v "${r}" '.[].latest | select(. == $v) // empty' "${eol}" 2>>"${LOG_FILE}"
            fi
            ;;
    esac
}

resolve_go() {
    local idx="/tmp/potenfyr-go-index.json"
    fetch_json "https://go.dev/dl/?mode=json&include=all" "${idx}" || fail_unresolved "go.dev download feed unreachable"
    case "${REQ}" in
        latest|stable|current|default|lts)
            jq -r '.[0].version // empty' "${idx}" 2>>"${LOG_FILE}" | sed 's/^go//' ;;
        alpha|beta|rc|pre|preview)
            local t
            t=$(jq -r '[.[].version | select(test("beta|rc|alpha"))][0] // empty' "${idx}" 2>>"${LOG_FILE}")
            if [ -n "${t}" ]; then v_info "INFO" "Go pre-release selected: ${t}"; echo "${t#go}"; return 0; fi
            v_info "WARN" "No Go pre-release available; using latest stable."
            jq -r '.[0].version // empty' "${idx}" 2>>"${LOG_FILE}" | sed 's/^go//' ;;
        nightly|dev|tip)
            v_info "WARN" "Go nightly requires 'gotip' source builds; selecting latest stable."
            jq -r '.[0].version // empty' "${idx}" 2>>"${LOG_FILE}" | sed 's/^go//' ;;
        *)
            local r="${REQ#v}"
            local hit
            hit=$(jq -r --arg p "go${r}" '[.[].version | select(startswith($p))][0] // empty' "${idx}" 2>>"${LOG_FILE}")
            [ -z "${hit}" ] && fail_unresolved "no Go release matches '${REQ}' (try 1.21, 1.22, latest)"
            echo "${hit#go}" ;;
    esac
}

resolve_rust() {
    case "${REQ}" in
        latest|stable|current|default|lts) echo "stable" ;;
        alpha|beta|rc|pre|preview)         echo "beta" ;;
        nightly|dev|tip|edge|canary)       echo "nightly" ;;
        *)                                 echo "${REQ#v}" ;;   # x.y.z concrete -> rustup resolves
    esac
}

resolve_java() {
    local rel="/tmp/potenfyr-java-rel.json"
    fetch_json "https://api.adoptium.net/v3/info/available_releases" "${rel}" || fail_unresolved "Adoptium release feed unreachable"
    local newest_lts newest_feature tip
    newest_lts=$(jq -r '.most_recent_lts // empty' "${rel}" 2>>"${LOG_FILE}")
    newest_feature=$(jq -r '.most_recent_feature_release // empty' "${rel}" 2>>"${LOG_FILE}")
    tip=$(jq -r '.tip_version // empty' "${rel}" 2>>"${LOG_FILE}")
    [ -z "${newest_lts}" ] && fail_unresolved "Adoptium feed returned no data"
    case "${REQ}" in
        latest|current|default)  echo "${newest_feature:-${newest_lts}}" ;;
        stable|lts)              echo "${newest_lts}" ;;
        alpha|beta|rc|pre|preview|nightly|dev|ea|tip)
            v_info "INFO" "Java early-access channel -> feature version ${tip} (ea builds)."
            echo "${tip}-ea" ;;
        *)
            local r="${REQ#v}"
            [[ "${r}" =~ ^[0-9]+ ]] || fail_unresolved "bad Java request '${REQ}'"
            local major="${r%%.*}"
            local known
            # available_releases is a JSON array of NUMBERS -> use --argjson
            if ! jq -e --argjson m "${major}" '.available_releases | index($m) != null' "${rel}" >/dev/null 2>>"${LOG_FILE}"; then
                fail_unresolved "JDK ${major} is not published by Adoptium. Available: $(jq -r '.available_releases | join(", ")' "${rel}" 2>>"${LOG_FILE}")"
            fi
            echo "${major}" ;;
    esac
}

resolve_dotnet() {
    case "${REQ}" in
        latest|stable|current|default) echo "LTS" ;;
        lts)                           echo "LTS" ;;
        alpha|beta|rc|pre|preview)     echo "STS:preview" ;;
        nightly|dev|tip|edge)          echo "STS:daily" ;;
        *)
            local r="${REQ#v}"
            [[ "${r}" =~ ^[0-9]+(\.[0-9]+){0,1}$ ]] || fail_unresolved ".NET channels look like 8, 8.0 / 9.0"
            [[ "${r}" =~ ^[0-9]+$ ]] && r="${r}.0"
            echo "${r}"
            ;;
    esac
}

resolve_zig() {
    local idx="/tmp/potenfyr-zig-index.json"
    fetch_json "https://ziglang.org/download/index.json" "${idx}" || fail_unresolved "ziglang.org index unreachable"
    case "${REQ}" in
        nightly|dev|tip|edge|master) echo "master"; return 0 ;;
        latest|stable|current|default|lts)
            jq -r 'keys[] | select(. != "master")' "${idx}" 2>>"${LOG_FILE}" | sort -V | tail -n1 ;;
        alpha|beta|rc|pre|preview)
            jq -r 'keys[] | select(. != "master")' "${idx}" 2>>"${LOG_FILE}" | sort -V | tail -n1 ;;
        *)
            local r="${REQ#v}"
            local hit
            hit=$(jq -r --arg v "${r}" 'keys[] | select(startswith($v))' "${idx}" 2>>"${LOG_FILE}" | sort -V | tail -n1)
            [ -z "${hit}" ] && fail_unresolved "no Zig version starts with '${REQ}'"
            echo "${hit}" ;;
    esac
}

resolve_dart() {
    local channel="stable" ver_url
    case "${REQ}" in
        latest|stable|current|default|lts) channel="stable" ;;
        alpha|beta|rc|pre|preview)         channel="beta" ;;
        nightly|dev|tip|edge|canary)       channel="dev" ;;
        *)
        local r="${REQ#v}"
            # exact versions live under their own release dirs
            echo "__EXACT__${r}"; return 0 ;;
    esac
    ver_url="https://storage.googleapis.com/dart-archive/channels/${channel}/release/latest/VERSION"
    local f="/tmp/potenfyr-dart-ver.json"
    fetch_json "${ver_url}" "${f}" || fail_unresolved "dart-archive ${channel} channel unreachable"
    local v
    v=$(jq -r '.version // empty' "${f}" 2>>"${LOG_FILE}")
    [ -n "${v}" ] && v_info "INFO" "Dart channel '${channel}' -> ${v}"
    echo "${v}"
}

# =============================================================================
# Dispatch
# =============================================================================
LANG_NORM="$(norm_lang "${LANG_IN}")"

# Re-key the cache now that the language is normalized, then try a TTL hit
CACHE_FILE="${CACHE_ROOT}/$( _cache_key "${LANG_NORM}__${REQ}" )"
cache_lookup

case "${LANG_NORM}" in
    nodejs)  RESOLVED="$(resolve_nodejs)" ;;
    bun)     RESOLVED="$(resolve_bun)" ;;
    deno)    RESOLVED="$(resolve_deno)" ;;
    python)  RESOLVED="$(resolve_python)" ;;
    go)      RESOLVED="$(resolve_go)" ;;
    rust)    RESOLVED="$(resolve_rust)" ;;
    java)    RESOLVED="$(resolve_java)" ;;
    dotnet)  RESOLVED="$(resolve_dotnet)" ;;
    zig)     RESOLVED="$(resolve_zig)" ;;
    dart)
        RESOLVED="$(resolve_dart)"
        [[ "${RESOLVED}" == __EXACT__* ]] && RESOLVED="${RESOLVED#__EXACT__}"
        ;;
    *)
        # Previously-pinned languages now resolve dynamically too. Anything not
        # covered below stays passthrough (validated) and the installer reports
        # exactly what it can and cannot honor.
        local eol="/tmp/potenfyr-eol-generic.json"
        case "${LANG_NORM}" in
            julia|nim|swift)
                # Different upstream feeds per language (endoflife lacks nim/swift)
                jf="/tmp/potenfyr-${LANG_NORM}-ver.json"
                if [ "${LANG_NORM}" = "julia" ]; then
                    fetch_json "https://endoflife.date/api/julia.json" "${jf}" || { RESOLVED="${REQ}"; }
                elif [ "${LANG_NORM}" = "nim" ]; then
                    fetch_json "https://api.github.com/repos/nim-lang/Nim/tags?per_page=60" "${jf}" || { RESOLVED="${REQ}"; }
                else
                    fetch_json "https://www.swift.org/api/v1/install/releases.json" "${jf}" || { RESOLVED="${REQ}"; }
                fi

                if [ -s "${jf}" ]; then
                    case "${LANG_NORM}" in
                        julia)
                            case "${REQ}" in
                                latest|stable|current|default|lts)
                                    RESOLVED=$(jq -r '.[0].latest // empty' "${jf}" 2>>"${LOG_FILE}") ;;
                                alpha|beta|rc|pre|preview|nightly|dev)
                                    RESOLVED=$(jq -r '.[0].latest // empty' "${jf}" 2>>"${LOG_FILE}") ;;
                                *)
                                    r="${REQ#v}"
                                    if [[ "${r}" =~ ^[0-9]+\.[0-9]+$ ]]; then
                                        RESOLVED=$(jq -r --arg c "${r}" '.[] | select(.cycle == $c) | .latest // empty' "${jf}" 2>>"${LOG_FILE}")
                                    elif [[ "${r}" =~ ^[0-9]+$ ]]; then
                                        RESOLVED=$(jq -r --arg c "${r}" '[.[] | select(.cycle | startswith($c + "."))][0].latest // empty' "${jf}" 2>>"${LOG_FILE}")
                                    else
                                        RESOLVED=$(jq -r --arg v "${r}" '.[].latest | select(. == $v) // empty' "${jf}" 2>>"${LOG_FILE}")
                                    fi
                                    ;;
                            esac
                            ;;
                        nim)
                            # First stable semver tag (skip rc/alpha/devel)
                            RESOLVED=$(jq -r '[.[].name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][0] // empty' "${jf}" 2>>"${LOG_FILE}" | sed 's/^v//')
                            if [[ "${REQ}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
                                r="${REQ#v}"
                                RESOLVED=$(jq -r --arg p "v${r}" '[.[].name | select(test("^" + $p + "(\\.[0-9]+)?$"))][0] // empty' "${jf}" 2>>"${LOG_FILE}" | sed 's/^v//')
                                [ -z "${RESOLVED}" ] && fail_unresolved "no Nim release starts with '${REQ}'"
                            fi
                            ;;
                        swift)
                            # entries look like {"name": "6.0.2", ...} (newest last)
                            RESOLVED=$(jq -r '.[-1].name // empty' "${jf}" 2>>"${LOG_FILE}")
                            if [[ "${REQ}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
                                r="${REQ#v}"
                                RESOLVED=$(jq -r --arg p "${r}" '[.[].name | select(test("^" + $p + "(\\.[0-9]+)?$"))][-1] // empty' "${jf}" 2>>"${LOG_FILE}")
                                [ -z "${RESOLVED}" ] && fail_unresolved "no Swift release matches '${REQ}'"
                            fi
                            ;;
                    esac
                    [ -z "${RESOLVED}" ] && fail_unresolved "no ${LANG_NORM} release matches '${REQ}'"
                else
                    v_warn "${LANG_NORM} feed unreachable; passing '${REQ}' to installer."
                    RESOLVED="${REQ}"
                fi
                ;;
            gleam)
                fetch_json "https://api.github.com/repos/gleam-lang/gleam/releases/latest" "/tmp/potenfyr-gleam.json" || \
                    fail_unresolved "GitHub feed unreachable"
                RESOLVED=$(jq -r '.tag_name // empty' "/tmp/potenfyr-gleam.json" 2>>"${LOG_FILE}" | sed 's/^v//')
                [ -z "${RESOLVED}" ] && fail_unresolved "could not read latest gleam tag"
                [[ "${REQ}" =~ ^[0-9] ]] && RESOLVED="${REQ#v}"
                ;;
            *)
                # Truly passthrough families (validated earlier)
                case "${REQ}" in
                    latest|stable|lts|current|default|alpha|beta|rc|pre|preview|nightly|dev|tip|edge|canary|master)
                        v_info "INFO" "${LANG_IN}: channel '${REQ}' accepted." ;;
                    *) : ;;
                esac
                RESOLVED="${REQ}"
                ;;
        esac
        ;;
esac

if [ -z "${RESOLVED:-}" ]; then
    fail_unresolved "resolver produced an empty result (upstream outage?)"
fi

_vlog "OK" "resolved ${LANG_IN} '${REQ}' -> '${RESOLVED}'"
v_info "RESOLVE" "${LANG_IN}: '${REQ}' -> ${RESOLVED}"
cache_store "${RESOLVED}"
printf '%s\n' "${RESOLVED}"
exit 0
