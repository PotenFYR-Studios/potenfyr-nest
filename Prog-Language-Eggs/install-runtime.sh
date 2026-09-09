#!/bin/bash
# =============================================================================
#  Multi-Language Eggs - Toolchain & Runtime Installer
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Prog-Language-Eggs)
#
#  Usage:
#    install-runtime.sh <language> [version] [target_dir]
#
#  Examples:
#    install-runtime.sh node 20
#    install-runtime.sh bun latest
#    install-runtime.sh python 3.12
#    install-runtime.sh java 21
#    install-runtime.sh go 1.22
#    install-runtime.sh rust stable
#    install-runtime.sh dotnet 8.0
#    install-runtime.sh zig 0.13.0
#    install-runtime.sh custom https://example.com/custom-runtime.tar.gz
# =============================================================================

set -e

# --- Visual formatting ---
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_CYAN=$'\033[36m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_BLUE=$'\033[34m'
C_DIM=$'\033[2m'

log()   { printf "%b %b\n" "${C_CYAN}${C_BOLD}[PotenFYR]${C_RESET}" "$*"; }
ok()    { printf "%b %b\n" "${C_GREEN}${C_BOLD}[PotenFYR][✓]${C_RESET}" "$*"; }
warn()  { printf "%b %b\n" "${C_YELLOW}${C_BOLD}[PotenFYR][!]${C_RESET}" "${C_YELLOW}$*${C_RESET}"; }
fail()  { printf "%b %b\n" "${C_RED}${C_BOLD}[PotenFYR][✗]${C_RESET}" "${C_RED}$*${C_RESET}"; exit 1; }
info()  { printf "%b %b\n" "${C_BLUE}${C_BOLD}[PotenFYR][i]${C_RESET}" "$*"; }

LANG_REQ="${1:-}"
VERSION_REQ="${2:-latest}"
# LANGUAGE_VERSION (panel alias, e.g. DB_VERSION-style vars) acts as a fallback
# when no explicit version argument was supplied.
if [ "${VERSION_REQ}" = "latest" ] && [ -n "${LANGUAGE_VERSION:-}" ]; then
    VERSION_REQ="${LANGUAGE_VERSION}"
fi
TARGET_BASE="${3:-/opt/runtimes}"

if [ -z "${LANG_REQ}" ]; then
    fail "No language specified. Usage: install-runtime.sh <language> [version]"
fi

# Detect system architecture (tolerant: ANY arch proceeds; each engine then
# checks its own upstream availability, so the egg works on every host CPU a
# panel can be hosted on - amd64, arm64, armv7 SBCs, ppc64le, s390x, riscv64).
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64|amd64)
        ARCH_FAMILY="amd64"; ARCH_ALT="x64";   ARCH_DEB="amd64";   ARCH_JAVA="x64"
        ARCH_RUST="x86_64-unknown-linux-gnu";  ARCH_GO="amd64";    ARCH_NODE="x64"
        ;;
    aarch64|arm64)
        ARCH_FAMILY="arm64"; ARCH_ALT="arm64"; ARCH_DEB="arm64";   ARCH_JAVA="aarch64"
        ARCH_RUST="aarch64-unknown-linux-gnu"; ARCH_GO="arm64";    ARCH_NODE="arm64"
        ;;
    armv7l|armv8l|armhf)
        ARCH="armv7l"
        ARCH_FAMILY="armv7"; ARCH_ALT="armv7l"; ARCH_DEB="armhf";  ARCH_JAVA="arm"
        ARCH_RUST="armv7-unknown-linux-gnueabihf"; ARCH_GO="armv6l"; ARCH_NODE="armv7l"
        ;;
    ppc64le)
        ARCH_FAMILY="ppc64le"; ARCH_ALT="ppc64le"; ARCH_DEB="ppc64el"; ARCH_JAVA="ppc64le"
        ARCH_RUST="powerpc64le-unknown-linux-gnu"; ARCH_GO="ppc64le";  ARCH_NODE="ppc64le"
        ;;
    s390x)
        ARCH_FAMILY="s390x"; ARCH_ALT="s390x"; ARCH_DEB="s390x";  ARCH_JAVA="s390x"
        ARCH_RUST="s390x-unknown-linux-gnu";  ARCH_GO="s390x";   ARCH_NODE="s390x"
        ;;
    riscv64)
        ARCH_FAMILY="riscv64"; ARCH_ALT="riscv64"; ARCH_DEB="riscv64"; ARCH_JAVA="riscv64"
        ARCH_RUST="riscv64gc-unknown-linux-gnu"; ARCH_GO="riscv64";   ARCH_NODE="riscv64"
        ;;
    *)
        # Unknown/unheard-of arch: continue with raw uname values as tokens and
        # let per-engine availability checks produce precise guidance.
        ARCH_FAMILY="${ARCH}"
        ARCH_ALT="${ARCH}"; ARCH_DEB="${ARCH}"; ARCH_JAVA="${ARCH}"
        ARCH_RUST="${ARCH}"; ARCH_GO="${ARCH}"; ARCH_NODE="${ARCH}"
        warn "Unrecognized architecture '${ARCH}'. Attempting best-effort install."
        ;;
esac

# engine_arch_supported <engine> <supported families...>
# Emits an actionable message and returns 1 when this engine cannot be
# provisioned on the current architecture. Never aborts other engines.
engine_arch_supported() {
    local engine="$1"; shift
    local f
    for f in "$@"; do
        [ "${f}" = "${ARCH_FAMILY}" ] && return 0
    done
    warn "'${engine}' has no official build for ${ARCH} (${ARCH_FAMILY})."
    warn "Fully supported on: $* . On this host use one of those engines, or run the panel node on amd64/arm64."
    return 1
}

USER_AGENT="ProgLanguageEggs/1.0 (PotenFYR Studios; Linux ${ARCH})"

# --- Supply-chain integrity ---------------------------------------------------
verify_sha256() { # verify_sha256 <file> <expected_hex> <label>
    local f="$1" expect="$2" label="${3:-artifact}" actual
    if ! command -v sha256sum >/dev/null 2>&1; then
        warn "sha256sum unavailable - skipping integrity check for ${label}."
        return 0
    fi
    if [ -z "${expect}" ]; then
        warn "No upstream checksum published for ${label} - proceeding without verification."
        return 0
    fi
    actual=$(sha256sum "${f}" 2>/dev/null | awk '{print $1}')
    if [ "${actual}" = "$(echo "${expect}" | tr '[:upper:]' '[:lower:]')" ]; then
        ok "Checksum verified (sha256) for ${label}"
        return 0
    fi
    fail "CHECKSUM MISMATCH for ${label}! expected=${expect} got=${actual}. Download corrupted or tampered - aborting."
}

# --- Egg-switch / upgrade migration -------------------------------------------
# Older releases installed some runtimes into unversioned directories. When a
# server moves between eggs or upgrades this installer, migrate the existing
# directory instead of re-downloading the whole toolchain.
migrate_legacy_dir() { # migrate_legacy_dir <legacy_path> <new_path>
    local legacy="$1" new="$2"
    [ -d "${legacy}" ] || return 0
    [ -e "${new}" ] && return 0
    if mv "${legacy}" "${new}" 2>>"${LOG_FILE:-/dev/null}"; then
        ok "Migrated existing installation: $(basename "${legacy}") -> $(basename "${new}")"
        # Refresh stable-name symlinks so PATH keeps working immediately
        if [ -d "${new}/bin" ]; then
            mkdir -p "$(dirname "${legacy}")/bin" 2>/dev/null || true
            local b
            for b in "${new}/bin"/*; do
                [ -f "${b}" ] && ln -sf "${b}" "${TARGET_BASE}/bin/$(basename "${b}")" 2>/dev/null || true
            done
        fi
    else
        warn "Could not migrate legacy directory ${legacy} (will install fresh to ${new})."
    fi
}

download() {
    local url="$1" dest="$2"
    if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 -A "${USER_AGENT}" -o "${dest}" "${url}"; then
        rm -f "${dest}"
        fail "Failed to download from ${url}"
    fi
}

if [ ! -w "${TARGET_BASE}" ] && [ ! -w "$(dirname "${TARGET_BASE}")" ]; then
    if [ -d "/home/container" ] && [ -w "/home/container" ]; then
        TARGET_BASE="/home/container/.runtimes"
    elif [ -d "/app" ] && [ -w "/app" ]; then
        TARGET_BASE="/app/.runtimes"
    elif [ -d "/server" ] && [ -w "/server" ]; then
        TARGET_BASE="/server/.runtimes"
    else
        TARGET_BASE="/tmp/runtimes"
    fi
fi
mkdir -p "${TARGET_BASE}" 2>/dev/null || true

LANG_LOWER=$(echo "${LANG_REQ}" | tr '[:upper:]' '[:lower:]')

# -----------------------------------------------------------------------------
# Dynamic version resolution & validation (fail-fast, live feeds)
#   * Rejects garbage BEFORE any download starts (clear guidance, exit 64)
#   * Maps keywords -> concrete versions: latest/stable/lts/alpha/beta/rc/
#     preview/nightly/canary/dev
#   * Concrete versions are verified against upstream feeds where available
# -----------------------------------------------------------------------------
RESOLVER_SCRIPT="/usr/local/bin/resolve-version.sh"
[ -f "${RESOLVER_SCRIPT}" ] || RESOLVER_SCRIPT="/resolve-version.sh"
if [ -f "${RESOLVER_SCRIPT}" ]; then
    log "Validating & resolving version request '${VERSION_REQ}' for '${LANG_LOWER}'..."
    if bash "${RESOLVER_SCRIPT}" "${LANG_LOWER}" "${VERSION_REQ}" > /tmp/potenfyr-resolved.ver; then
        RESOLVED_VERSION=$(cat /tmp/potenfyr-resolved.ver 2>/dev/null)
        rm -f /tmp/potenfyr-resolved.ver
        if [ -n "${RESOLVED_VERSION}" ]; then
            VERSION_REQ="${RESOLVED_VERSION}"
            ok "Using ${LANG_LOWER} version: ${VERSION_REQ}"
        fi
    else
        rm -f /tmp/potenfyr-resolved.ver
        # Resolver already printed a detailed, user-facing explanation on console
        fail "Invalid or unresolvable version request for '${LANG_LOWER}'. Nothing was downloaded."
    fi
fi

case "${LANG_LOWER}" in
    # -------------------------------------------------------------------------
    # Node.js / JavaScript / TypeScript
    # -------------------------------------------------------------------------
    node|nodejs|javascript|js)
        # Official dists: x64, arm64, armv7l, ppc64le, s390x (+ riscv64 experimental)
        engine_arch_supported node amd64 arm64 armv7 ppc64le s390x || exit 0
        if command -v node >/dev/null 2>&1 && [ "${VERSION_REQ}" = "latest" -o "${VERSION_REQ}" = "default" -o -z "${VERSION_REQ}" ]; then
            ok "Node.js $(node -v 2>/dev/null) is already installed and ready"
            exit 0
        fi
        log "Resolving Node.js runtime (version: ${VERSION_REQ})..."
        if [ "${VERSION_REQ}" = "latest" ] || [ "${VERSION_REQ}" = "lts" ] || [ -z "${VERSION_REQ}" ]; then
            NODE_VER=$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null | jq -r '[.[] | select(.lts != false)][0].version' || echo "v20.18.0")
        elif [[ "${VERSION_REQ}" =~ ^v?[0-9]+$ ]]; then
            MAJOR="${VERSION_REQ#v}"
            NODE_VER=$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null | jq -r --arg m "v${MAJOR}." '[.[] | select(.version | startswith($m))][0].version' || echo "v${MAJOR}.0.0")
        else
            [[ "${VERSION_REQ}" =~ ^v ]] && NODE_VER="${VERSION_REQ}" || NODE_VER="v${VERSION_REQ}"
        fi

        # Nightly builds live on a separate CDN path (resolver emits them for 'nightly')
        NODE_BASE="https://nodejs.org/dist"
        [[ "${NODE_VER}" == *nightly* ]] && NODE_BASE="https://nodejs.org/download/nightly"

        DEST_DIR="${TARGET_BASE}/node-${NODE_VER}"
        if [ -x "${DEST_DIR}/bin/node" ]; then
            ok "Node.js ${NODE_VER} is already installed at ${DEST_DIR}"
        else
            log "Downloading Node.js ${NODE_VER} for ${ARCH_NODE}..."
            TAR_URL="${NODE_BASE}/${NODE_VER}/node-${NODE_VER}-linux-${ARCH_NODE}.tar.xz"
            TMP_TAR="/tmp/node.tar.xz"
            download "${TAR_URL}" "${TMP_TAR}"
            # Verify against the official SHASUMS256.txt published beside the tarball
            NODE_SHA=$(curl -fsSL --max-time 30 "${NODE_BASE}/${NODE_VER}/SHASUMS256.txt" 2>/dev/null \
                | awk -v f="node-${NODE_VER}-linux-${ARCH_NODE}.tar.xz" '$2 == f {print $1}')
            verify_sha256 "${TMP_TAR}" "${NODE_SHA}" "Node.js ${NODE_VER}"
            mkdir -p "${DEST_DIR}"
            tar -xJf "${TMP_TAR}" --strip-components=1 -C "${DEST_DIR}"
            rm -f "${TMP_TAR}"
            ok "Installed Node.js ${NODE_VER} to ${DEST_DIR}"
        fi
        
        export PATH="${DEST_DIR}/bin:${PATH}"
        npm install -g --no-fund --no-audit npm pnpm yarn typescript ts-node tsx nodemon pm2 2>/dev/null || true
        ;;

    # -------------------------------------------------------------------------
    # Bun
    bun)
        engine_arch_supported bun amd64 arm64 || exit 0
        if command -v bun >/dev/null 2>&1; then
            ok "Bun $(bun -v 2>/dev/null || true) is already available"
            exit 0
        fi
        log "Resolving Bun runtime (version: ${VERSION_REQ:-latest})..."
        DEST_DIR="${TARGET_BASE}/bun-${VERSION_REQ:-latest}"
        migrate_legacy_dir "${TARGET_BASE}/bun" "${DEST_DIR}"
        mkdir -p "${DEST_DIR}/bin"
        if [ "${ARCH_ALT}" = "x64" ]; then
            BUN_ARCH="x64"
        else
            BUN_ARCH="aarch64"
        fi
        # Concrete versions download from their release tag; keywords from /latest/
        if [[ "${VERSION_REQ:-}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
            BUN_URL="https://github.com/oven-sh/bun/releases/download/bun-v${VERSION_REQ}/bun-linux-${BUN_ARCH}.zip"
        else
            BUN_URL="https://github.com/oven-sh/bun/releases/latest/download/bun-linux-${BUN_ARCH}.zip"
        fi
        TMP_ZIP="/tmp/bun.zip"
        download "${BUN_URL}" "${TMP_ZIP}"
        rm -rf /tmp/bun-extract && mkdir -p /tmp/bun-extract
        unzip -qo "${TMP_ZIP}" -d /tmp/bun-extract
        if [ -f "/tmp/bun-extract/bun-linux-${BUN_ARCH}/bun" ]; then
            mv -f "/tmp/bun-extract/bun-linux-${BUN_ARCH}/bun" "${DEST_DIR}/bin/bun"
        elif [ -f "/tmp/bun-extract/bun" ]; then
            mv -f "/tmp/bun-extract/bun" "${DEST_DIR}/bin/bun"
        else
            find /tmp/bun-extract -type f -name "bun" -exec mv -f {} "${DEST_DIR}/bin/bun" \;
        fi
        chmod +x "${DEST_DIR}/bin/bun" 2>/dev/null || true
        ln -sf "${DEST_DIR}/bin/bun" "${DEST_DIR}/bin/bunx" 2>/dev/null || true
        rm -rf "${TMP_ZIP}" /tmp/bun-extract
        ok "Installed Bun to ${DEST_DIR}/bin/bun"
        ;;

    # -------------------------------------------------------------------------
    # Deno
    deno)
        engine_arch_supported deno amd64 arm64 || exit 0
        if command -v deno >/dev/null 2>&1; then
            ok "Deno $(deno -V 2>/dev/null || true) is already available"
            exit 0
        fi
        log "Resolving Deno runtime (version: ${VERSION_REQ:-latest})..."
        DEST_DIR="${TARGET_BASE}/deno-${VERSION_REQ:-latest}"
        migrate_legacy_dir "${TARGET_BASE}/deno" "${DEST_DIR}"
        mkdir -p "${DEST_DIR}/bin"
        DENO_ARCH="${ARCH}"
        [ "${DENO_ARCH}" = "arm64" ] && DENO_ARCH="aarch64"
        if [[ "${VERSION_REQ:-}" =~ ^[0-9]+(\.[0-9]+){0,2}([-.][A-Za-z0-9.]+)*$ ]]; then
            DENO_URL="https://github.com/denoland/deno/releases/download/v${VERSION_REQ}/deno-${DENO_ARCH}-unknown-linux-gnu.zip"
        else
            DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-${DENO_ARCH}-unknown-linux-gnu.zip"
        fi
        TMP_ZIP="/tmp/deno.zip"
        download "${DENO_URL}" "${TMP_ZIP}"
        unzip -qo "${TMP_ZIP}" -d "${DEST_DIR}/bin"
        chmod +x "${DEST_DIR}/bin/deno" 2>/dev/null || true
        rm -f "${TMP_ZIP}"
        ok "Installed Deno to ${DEST_DIR}/bin/deno"
        ;;

    # -------------------------------------------------------------------------
    # Python & Package Managers (pip, poetry, uv, pipenv)
    # -------------------------------------------------------------------------
    python|python3|py)
        # uv ships x86_64/aarch64 only; other arches fall back to apt system python3/pip
        if ! engine_arch_supported uv amd64 arm64; then
            warn "Skipping uv - using the distro python3 already present in the image."
            exit 0
        fi
        log "Setting up Python environment and tools (uv, poetry, pipenv)..."
        DEST_DIR="${TARGET_BASE}/python"
        mkdir -p "${DEST_DIR}/bin"
        
        # Install Astral uv (ultra-fast Python package & version manager)
        UV_ARCH="${ARCH}"
        [ "${UV_ARCH}" = "arm64" ] && UV_ARCH="aarch64"
        UV_URL="https://github.com/astral-sh/uv/releases/latest/download/uv-${UV_ARCH}-unknown-linux-gnu.tar.gz"
        TMP_TAR="/tmp/uv.tar.gz"
        if curl -fsSL -o "${TMP_TAR}" "${UV_URL}"; then
            tar -xzf "${TMP_TAR}" -C /tmp
            mv /tmp/uv-*/uv /tmp/uv-*/uvx "${DEST_DIR}/bin/" 2>/dev/null || true
            chmod +x "${DEST_DIR}/bin/uv" "${DEST_DIR}/bin/uvx" 2>/dev/null || true
            rm -rf "${TMP_TAR}" /tmp/uv-*
            ok "Installed uv & uvx toolchain"
        fi
        # Respect a concrete Python version request via uv (e.g. RUNTIME_VERSION=3.12)
        if [[ "${VERSION_REQ}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
            log "Installing Python ${VERSION_REQ} toolchain via uv..."
            if "${DEST_DIR}/bin/uv" python install "${VERSION_REQ}" >>/tmp/potenfyr-uv-python.log 2>&1; then
                ok "Python ${VERSION_REQ} installed (managed by uv)"
            else
                warn "Could not install Python ${VERSION_REQ} via uv (see /tmp/potenfyr-uv-python.log); system python3 stays active."
            fi
        fi
        ;;

    # -------------------------------------------------------------------------
    # Java (Adoptium Temurin OpenJDK 8, 11, 17, 21, 25, 26+)
    # -------------------------------------------------------------------------
    java|jdk|openjdk)
        engine_arch_supported java amd64 arm64 armv7 ppc64le s390x riscv64 || exit 0
        JV="${VERSION_REQ}"
        [ "${JV}" = "latest" ] && JV="21"
        JV="${JV#java}"
        JV="${JV#jdk}"

        # Early-access channel support: resolver emits "<major>-ea" for preview/nightly
        JAVA_RELEASE_TYPE="ga"
        if [[ "${JV}" == *-ea ]]; then
            JAVA_RELEASE_TYPE="ea"
            JV="${JV%-ea}"
        fi

        DEST_DIR="${TARGET_BASE}/java-${JV}$([ "${JAVA_RELEASE_TYPE}" = "ea" ] && echo "-ea" || true)"
        if [ -x "${DEST_DIR}/bin/java" ]; then
            ok "Java ${JV} already installed at ${DEST_DIR}"
        else
            log "Downloading Adoptium OpenJDK ${JV} (${JAVA_RELEASE_TYPE}) for ${ARCH_JAVA}..."
            API_URL="https://api.adoptium.net/v3/binary/latest/${JV}/${JAVA_RELEASE_TYPE}/linux/${ARCH_JAVA}/jdk/hotspot/normal/eclipse?project=jdk"
            TMP_TAR="/tmp/jdk${JV}.tar.gz"
            download "${API_URL}" "${TMP_TAR}"
            mkdir -p "${DEST_DIR}"
            tar -xzf "${TMP_TAR}" --strip-components=1 -C "${DEST_DIR}"
            rm -f "${TMP_TAR}"
            ok "Installed Adoptium OpenJDK ${JV} to ${DEST_DIR}"
        fi
        ;;

    # -------------------------------------------------------------------------
    # Go (Golang)
    # -------------------------------------------------------------------------
    go|golang)
        engine_arch_supported golang amd64 arm64 armv7 ppc64le s390x riscv64 || exit 0
        log "Resolving Go toolchain (version: ${VERSION_REQ})..."
        if [ "${VERSION_REQ}" = "latest" ] || [ -z "${VERSION_REQ}" ]; then
            GO_VER=$(curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '.[0].version')
        else
            [[ "${VERSION_REQ}" =~ ^go ]] && GO_VER="${VERSION_REQ}" || GO_VER="go${VERSION_REQ}"
        fi
        
        DEST_DIR="${TARGET_BASE}/${GO_VER}"
        if [ -x "${DEST_DIR}/bin/go" ]; then
            ok "Go ${GO_VER} already installed at ${DEST_DIR}"
        else
            GO_URL="https://go.dev/dl/${GO_VER}.linux-${ARCH_GO}.tar.gz"
            TMP_TAR="/tmp/go.tar.gz"
            download "${GO_URL}" "${TMP_TAR}"
            mkdir -p "${DEST_DIR}"
            tar -xzf "${TMP_TAR}" --strip-components=1 -C "${DEST_DIR}"
            rm -f "${TMP_TAR}"
            ok "Installed ${GO_VER} to ${DEST_DIR}"
        fi
        ;;

    # -------------------------------------------------------------------------
    # Rust & Cargo
    # -------------------------------------------------------------------------
    rust|cargo|rustc)
        # VERSION_REQ arrives pre-resolved: stable | beta | nightly | <x.y.z>
        RUST_TOOLCHAIN="${VERSION_REQ:-stable}"
        case "${RUST_TOOLCHAIN}" in
            stable|beta|nightly) : ;;
            *) [[ "${RUST_TOOLCHAIN}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || RUST_TOOLCHAIN="stable" ;;
        esac
        log "Setting up Rust toolchain via rustup (channel: ${RUST_TOOLCHAIN})..."
        export RUSTUP_HOME="${TARGET_BASE}/rustup"
        export CARGO_HOME="${TARGET_BASE}/cargo-${RUST_TOOLCHAIN}"
        migrate_legacy_dir "${TARGET_BASE}/cargo" "${CARGO_HOME}"
        mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "${RUST_TOOLCHAIN}" --no-modify-path \
            || warn "rustup installation failed for toolchain '${RUST_TOOLCHAIN}'."
        ok "Rust (${RUST_TOOLCHAIN}) & Cargo toolchain ready at ${CARGO_HOME}/bin"
        ;;

    # -------------------------------------------------------------------------
    # Zig
    # -------------------------------------------------------------------------
    zig)
        engine_arch_supported zig amd64 arm64 || exit 0
        log "Resolving Zig compiler (version: ${VERSION_REQ})..."
        ZIG_ARCH="${ARCH}"
        [ "${ZIG_ARCH}" = "arm64" ] && ZIG_ARCH="aarch64"
        if [ "${VERSION_REQ}" = "latest" ] || [ "${VERSION_REQ}" = "master" ] || [ -z "${VERSION_REQ}" ]; then
            ZIG_URL=$(curl -fsSL https://ziglang.org/download/index.json | jq -r ".master.\"${ZIG_ARCH}-linux\".tarball")
            ZIG_SUM=$(curl -fsSL https://ziglang.org/download/index.json | jq -r ".master.\"${ZIG_ARCH}-linux\".shasum")
        else
            ZIG_URL=$(curl -fsSL https://ziglang.org/download/index.json | jq -r ".\"${VERSION_REQ}\".\"${ZIG_ARCH}-linux\".tarball")
            ZIG_SUM=$(curl -fsSL https://ziglang.org/download/index.json | jq -r ".\"${VERSION_REQ}\".\"${ZIG_ARCH}-linux\".shasum")
        fi

        DEST_DIR="${TARGET_BASE}/zig"
        TMP_TAR="/tmp/zig.tar.xz"
        download "${ZIG_URL}" "${TMP_TAR}"
        verify_sha256 "${TMP_TAR}" "${ZIG_SUM}" "Zig ${VERSION_REQ}"
        mkdir -p "${DEST_DIR}"
        tar -xJf "${TMP_TAR}" --strip-components=1 -C "${DEST_DIR}"
        rm -f "${TMP_TAR}"
        ok "Installed Zig to ${DEST_DIR}/zig"
        ;;

    # -------------------------------------------------------------------------
    # .NET SDK (C#, F#, VB.NET)
    # -------------------------------------------------------------------------
    dotnet|csharp|fsharp|vb)
        # .NET ships linux x64/arm64/arm(32) only - no ppc64le/s390x/riscv64
        engine_arch_supported dotnet amd64 arm64 armv7 || exit 0
        log "Setting up .NET SDK (channel: ${VERSION_REQ:-LTS})..."
        DEST_DIR="${TARGET_BASE}/dotnet"
        mkdir -p "${DEST_DIR}"
        TMP_SH="/tmp/dotnet-install.sh"
        download "https://dot.net/v1/dotnet-install.sh" "${TMP_SH}"
        chmod +x "${TMP_SH}"
        # Resolver emits: LTS | STS:preview | STS:daily | <major.minor>
        DOTNET_CHANNEL="LTS"; DOTNET_QUALITY="GA"
        case "${VERSION_REQ}" in
            LTS|"")                     DOTNET_CHANNEL="LTS";  DOTNET_QUALITY="GA" ;;
            STS:preview|preview|alpha|beta|rc|pre) DOTNET_CHANNEL="STS";  DOTNET_QUALITY="Preview" ;;
            STS:daily|nightly|dev)      DOTNET_CHANNEL="STS";  DOTNET_QUALITY="Daily" ;;
            *)                          DOTNET_CHANNEL="${VERSION_REQ}"; DOTNET_QUALITY="GA" ;;
        esac
        log ".NET install -> channel=${DOTNET_CHANNEL} quality=${DOTNET_QUALITY}"
        bash "${TMP_SH}" --channel "${DOTNET_CHANNEL}" --quality "${DOTNET_QUALITY}" --install-dir "${DEST_DIR}" --no-path
        rm -f "${TMP_SH}"
        ok "Installed .NET SDK to ${DEST_DIR}/dotnet"
        ;;

    # -------------------------------------------------------------------------
    # Swift
    # -------------------------------------------------------------------------
    swift)
        # VERSION_REQ resolved from swift.org releases feed; fall back to a known
        # good pin ONLY if the requested build is unavailable for this platform.
        log "Resolving Swift toolchain (version: ${VERSION_REQ:-latest})..."
        DEST_DIR="${TARGET_BASE}/swift"
        SWIFT_ARCH="${ARCH}"
        [ "${SWIFT_ARCH}" = "arm64" ] && SWIFT_ARCH="aarch64"
        TMP_TAR="/tmp/swift.tar.gz"
        SWIFT_CANDIDATES=()
        if [[ "${VERSION_REQ:-}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            SWIFT_BASE="${VERSION_REQ%.*}"
            SWIFT_CANDIDATES+=("https://download.swift.org/swift-${VERSION_REQ}-release/ubuntu2204/swift-${VERSION_REQ}-RELEASE/swift-${VERSION_REQ}-RELEASE-ubuntu22.04-${SWIFT_ARCH}.tar.gz")
        fi
        SWIFT_CANDIDATES+=("https://download.swift.org/swift-5.10.1-release/ubuntu2204/swift-5.10.1-RELEASE/swift-5.10.1-RELEASE-ubuntu22.04-${SWIFT_ARCH}.tar.gz")
        SWIFT_OK=0
        for SWIFT_URL in "${SWIFT_CANDIDATES[@]}"; do
            if curl -fsSL --max-time 900 -o "${TMP_TAR}" "${SWIFT_URL}"; then
                mkdir -p "${DEST_DIR}"
                tar -xzf "${TMP_TAR}" --strip-components=1 -C "${DEST_DIR}" \
                    && SWIFT_OK=1 && ok "Installed Swift ($(basename "${SWIFT_URL}" | cut -d- -f2)) to ${DEST_DIR}"
                rm -f "${TMP_TAR}"
                [ "${SWIFT_OK}" = "1" ] && break
            fi
        done
        [ "${SWIFT_OK}" = "0" ] && warn "No Swift build succeeded for ${ARCH}; skipping (system clang can still compile Swift-style C)."
        ;;

    # -------------------------------------------------------------------------
    # Julia
    # -------------------------------------------------------------------------
    julia)
        # VERSION_REQ resolved from endoflife.date julia feed; URL layout:
        # /bin/linux/<dir>/<series>/julia-<full>-linux-<file>.tar.gz
        log "Resolving Julia runtime (version: ${VERSION_REQ:-latest})..."
        DEST_DIR="${TARGET_BASE}/julia"
        case "${ARCH}" in
            x86_64|amd64) JDIR="x64";     JFILE="x86_64" ;;
            aarch64|arm64) JDIR="aarch64"; JFILE="aarch64" ;;
            armv7l)        JDIR="armv7l";  JFILE="armv7l" ;;
            ppc64le)       JDIR="ppc64le"; JFILE="powerpc64le" ;;
            *)             JDIR="x64";     JFILE="x86_64" ;;
        esac
        TMP_TAR="/tmp/julia.tar.gz"
        JULIA_CANDIDATES=()
        if [[ "${VERSION_REQ:-}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            JSERIES="${VERSION_REQ%.*}"
            JULIA_CANDIDATES+=("https://julialang-s3.julialang.org/bin/linux/${JDIR}/${JSERIES}/julia-${VERSION_REQ}-linux-${JFILE}.tar.gz")
        fi
        JULIA_CANDIDATES+=("https://julialang-s3.julialang.org/bin/linux/${JDIR}/1.10/julia-1.10.4-linux-${JFILE}.tar.gz")
        JULIA_OK=0
        for JULIA_URL in "${JULIA_CANDIDATES[@]}"; do
            if download "${JULIA_URL}" "${TMP_TAR}"; then
                mkdir -p "${DEST_DIR}"
                if tar -xzf "${TMP_TAR}" --strip-components=1 -C "${DEST_DIR}"; then
                    JULIA_OK=1; rm -f "${TMP_TAR}"; break
                fi
                rm -f "${TMP_TAR}"
            fi
        done
        [ "${JULIA_OK}" = "1" ] && ok "Installed Julia to ${DEST_DIR}" \
            || warn "Julia install failed for ${ARCH} (requested: ${VERSION_REQ})."
        ;;

    # -------------------------------------------------------------------------
    # Dart
    # -------------------------------------------------------------------------
    dart)
        engine_arch_supported dart amd64 arm64 || exit 0
        log "Resolving Dart SDK..."
        DEST_DIR="${TARGET_BASE}/dart-sdk"
        DART_ARCH="${ARCH}"
        [ "${DART_ARCH}" = "amd64" ] || [ "${DART_ARCH}" = "x86_64" ] && DART_ARCH="x64"
        DART_URL="https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-${DART_ARCH}-release.zip"
        TMP_ZIP="/tmp/dart.zip"
        download "${DART_URL}" "${TMP_ZIP}"
        unzip -qo "${TMP_ZIP}" -d "${TARGET_BASE}"
        rm -f "${TMP_ZIP}"
        ok "Installed Dart SDK to ${DEST_DIR}"
        ;;

    # -------------------------------------------------------------------------
    # Odin
    # -------------------------------------------------------------------------
    odin)
        log "Resolving Odin programming language..."
        DEST_DIR="${TARGET_BASE}/odin"
        mkdir -p "${DEST_DIR}"
        ODIN_URL="https://github.com/odin-lang/Odin/releases/latest/download/odin-linux-amd64.tar.gz"
        if [ "${ARCH_DEB}" = "amd64" ]; then
            TMP_TAR="/tmp/odin.tar.gz"
            download "${ODIN_URL}" "${TMP_TAR}"
            tar -xzf "${TMP_TAR}" -C "${DEST_DIR}"
            rm -f "${TMP_TAR}"
            ok "Installed Odin to ${DEST_DIR}"
        fi
        ;;

    # -------------------------------------------------------------------------
    # Gleam
    # -------------------------------------------------------------------------
    gleam)
        # VERSION_REQ resolved from GitHub releases feed; asset uses rust triple
        log "Resolving Gleam compiler (version: ${VERSION_REQ:-latest})..."
        DEST_DIR="${TARGET_BASE}/gleam/bin"
        mkdir -p "${DEST_DIR}"
        GLEAM_ARCH="${ARCH_RUST}"
        TMP_TAR="/tmp/gleam.tar.gz"
        GLEAM_CANDIDATES=()
        if [[ "${VERSION_REQ:-}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            GLEAM_CANDIDATES+=("https://github.com/gleam-lang/gleam/releases/download/v${VERSION_REQ}/gleam-v${VERSION_REQ}-${GLEAM_ARCH}.tar.gz")
        fi
        GLEAM_CANDIDATES+=("https://github.com/gleam-lang/gleam/releases/latest/download/gleam-v1.4.1-${GLEAM_ARCH}.tar.gz")
        GLEAM_OK=0
        for GLEAM_URL in "${GLEAM_CANDIDATES[@]}"; do
            if curl -fsSL --max-time 300 -o "${TMP_TAR}" "${GLEAM_URL}"; then
                tar -xzf "${TMP_TAR}" -C "${DEST_DIR}" && GLEAM_OK=1
                rm -f "${TMP_TAR}"
                [ "${GLEAM_OK}" = "1" ] && chmod +x "${DEST_DIR}/gleam" 2>/dev/null && break
            fi
        done
        [ "${GLEAM_OK}" = "1" ] && ok "Installed Gleam to ${DEST_DIR}/gleam" \
            || warn "Gleam install failed for ${GLEAM_ARCH} (requested: ${VERSION_REQ})."
        ;;

    # -------------------------------------------------------------------------
    # Nim
    # -------------------------------------------------------------------------
    nim)
        # VERSION_REQ resolved from nim-lang/Nim GitHub tags; binaries live on
        # nim-lang.org with per-version names. Falls back to known-good pin.
        log "Setting up Nim (version: ${VERSION_REQ:-latest})..."
        DEST_DIR="${TARGET_BASE}/nim"
        NIM_ARCH="${ARCH_ALT}"
        TMP_TAR="/tmp/nim.tar.xz"
        NIM_CANDIDATES=()
        if [[ "${VERSION_REQ:-}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            NIM_CANDIDATES+=("https://nim-lang.org/download/nim-${VERSION_REQ}-linux_${NIM_ARCH}.tar.xz")
        fi
        NIM_CANDIDATES+=("https://nim-lang.org/download/nim-2.0.8-linux_${NIM_ARCH}.tar.xz")
        NIM_OK=0
        for NIM_URL in "${NIM_CANDIDATES[@]}"; do
            if curl -fsSL --max-time 600 -o "${TMP_TAR}" "${NIM_URL}"; then
                mkdir -p "${DEST_DIR}"
                if tar -xJf "${TMP_TAR}" --strip-components=1 -C "${DEST_DIR}"; then
                    NIM_OK=1; rm -f "${TMP_TAR}"; break
                fi
                rm -f "${TMP_TAR}"
            fi
        done
        [ "${NIM_OK}" = "1" ] && ok "Installed Nim to ${DEST_DIR}" \
            || warn "Nim install failed for ${ARCH} (requested: ${VERSION_REQ})."
        ;;

    # -------------------------------------------------------------------------
    # Custom Download URL
    # -------------------------------------------------------------------------
    custom)
        [ -n "${VERSION_REQ}" ] || fail "Custom runtime requires a URL as the second parameter"
        log "Downloading custom runtime archive from ${VERSION_REQ}..."
        DEST_DIR="${TARGET_BASE}/custom"
        mkdir -p "${DEST_DIR}"
        TMP_ARCHIVE="/tmp/custom-runtime"
        download "${VERSION_REQ}" "${TMP_ARCHIVE}"
        case "${VERSION_REQ}" in
            *.tar.gz|*.tgz)
                tar -xzf "${TMP_ARCHIVE}" -C "${DEST_DIR}"
                ;;
            *.tar.xz)
                tar -xJf "${TMP_ARCHIVE}" -C "${DEST_DIR}"
                ;;
            *.zip)
                unzip -qo "${TMP_ARCHIVE}" -d "${DEST_DIR}"
                ;;
            *)
                mv "${TMP_ARCHIVE}" "${DEST_DIR}/custom-binary"
                chmod +x "${DEST_DIR}/custom-binary"
                ;;
        esac
        chmod -R +x "${DEST_DIR}" 2>/dev/null || true
        for bin in "${DEST_DIR}"/*; do
            [ -f "${bin}" ] && [ -x "${bin}" ] && ln -sf "${bin}" "/usr/local/bin/$(basename "${bin}")" 2>/dev/null || true
        done
        rm -f "${TMP_ARCHIVE}"
        ok "Custom runtime installed to ${DEST_DIR} and linked to PATH"
        ;;

    *)
        log "Language '${LANG_REQ}' relies on pre-installed system packages or custom setup."
        ;;
esac

if [ -n "${DEST_DIR:-}" ] && [ -d "${DEST_DIR}" ]; then
    mkdir -p "${TARGET_BASE}/bin" 2>/dev/null || true
    if [ -d "${DEST_DIR}/bin" ]; then
        for bin in "${DEST_DIR}/bin"/*; do
            [ -f "${bin}" ] && [ -x "${bin}" ] && ln -sf "${bin}" "${TARGET_BASE}/bin/$(basename "${bin}")" 2>/dev/null || true
        done
    else
        for bin in "${DEST_DIR}"/*; do
            [ -f "${bin}" ] && [ -x "${bin}" ] && ln -sf "${bin}" "${TARGET_BASE}/bin/$(basename "${bin}")" 2>/dev/null || true
        done
    fi
fi
