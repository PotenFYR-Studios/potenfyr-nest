#!/bin/bash
#
# Multi Minecraft - Universal Java runtime installer
#
# Downloads, extracts, and configures any Java runtime (Adoptium, GraalVM, Corretto,
# Semeru/OpenJ9, Zulu, or any custom direct download URL) into /opt/java/<name>
# (with transparent fallback to ~/.java/<name> if /opt/java is not writable).
#
# Usage:
#   install-java.sh <version_or_vendor_or_url> [arch_or_target_name]
#
# Examples:
#   install-java.sh 26
#   install-java.sh 27
#   install-java.sh graalvm-21
#   install-java.sh corretto-21
#   install-java.sh https://example.com/custom-jdk.tar.gz custom

set -euo pipefail

INPUT="${1:-}"
ARCH="${2:-}"

if [ -z "${INPUT}" ]; then
    echo "Usage: install-java.sh <version_or_vendor_or_url> [arch_or_target_name]" >&2
    exit 1
fi

DETECTED_ARCH=""
case "$(uname -m)" in
    x86_64|amd64) DETECTED_ARCH="x64" ;;
    aarch64|arm64) DETECTED_ARCH="aarch64" ;;
    ppc64le|ppc64) DETECTED_ARCH="ppc64le" ;;
    s390x) DETECTED_ARCH="s390x" ;;
    riscv64) DETECTED_ARCH="riscv64" ;;
    *) DETECTED_ARCH="$(uname -m)" ;;
esac

# Normalize arch (Adoptium naming); unknown values pass through untouched so
# exotic architectures can still resolve if the vendor publishes them.
if [ -n "${ARCH}" ]; then
    case "${ARCH}" in
        amd64) ARCH="x64" ;;
        arm64) ARCH="aarch64" ;;
        x64|aarch64|ppc64le|s390x|riscv64) ;;
        *) ARCH="${DETECTED_ARCH}" ;;
    esac
else
    ARCH="${DETECTED_ARCH}"
fi

TARGET_NAME=""
CUSTOM_URL=""

if [[ "${INPUT}" =~ ^https?:// ]]; then
    CUSTOM_URL="${INPUT}"
    TARGET_NAME="${2:-custom}"
    if [ "${TARGET_NAME}" = "x64" ] || [ "${TARGET_NAME}" = "aarch64" ]; then
        TARGET_NAME="custom"
    fi
else
    TARGET_NAME="${INPUT}"
fi

# Pick install directory: prefer /opt/java, fallback to ~/.java if unprivileged
TARGET_DIR="/opt/java/${TARGET_NAME}"
if [ ! -w "/opt/java" ] 2>/dev/null && [ "$(id -u)" -ne 0 ]; then
    TARGET_DIR="${HOME:-/home/container}/.java/${TARGET_NAME}"
fi

# If already installed and functional, return immediately
if [ -x "${TARGET_DIR}/bin/java" ]; then
    echo "Java (${TARGET_NAME}) is already installed at ${TARGET_DIR}"
    exit 0
fi

echo "Resolving and installing Java runtime '${TARGET_NAME}' (${ARCH})..."

TMP_ARCHIVE="/tmp/java_dl_${TARGET_NAME}_$$"
trap 'rm -f "${TMP_ARCHIVE}"' EXIT

CANDIDATE_URLS=()

if [ -n "${CUSTOM_URL}" ]; then
    CANDIDATE_URLS+=("${CUSTOM_URL}")
elif [[ "${INPUT}" =~ ^graalvm-?([0-9]+)?$ ]]; then
    GV_VER="${BASH_REMATCH[1]:-21}"
    if [ "${ARCH}" = "x64" ]; then
        CANDIDATE_URLS+=("https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-${GV_VER}.0.2/graalvm-community-jdk-${GV_VER}.0.2_linux-x64_bin.tar.gz")
    elif [ "${ARCH}" = "aarch64" ]; then
        CANDIDATE_URLS+=("https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-${GV_VER}.0.2/graalvm-community-jdk-${GV_VER}.0.2_linux-aarch64_bin.tar.gz")
    fi
elif [[ "${INPUT}" =~ ^corretto-?([0-9]+)?$ ]]; then
    CORR_VER="${BASH_REMATCH[1]:-21}"
    CORR_ARCH="${ARCH}"
    CANDIDATE_URLS+=("https://corretto.aws/downloads/latest/amazon-corretto-${CORR_VER}-${CORR_ARCH}-linux-jdk.tar.gz")
elif [[ "${INPUT}" =~ ^semeru-?([0-9]+)?$ ]] || [[ "${INPUT}" =~ ^openj9-?([0-9]+)?$ ]]; then
    SEM_VER="${BASH_REMATCH[1]:-21}"
    CANDIDATE_URLS+=(
        "https://api.adoptium.net/v3/binary/latest/${SEM_VER}/ga/linux/${ARCH}/jre/openj9/normal/semeru"
        "https://api.adoptium.net/v3/binary/latest/${SEM_VER}/ga/linux/${ARCH}/jdk/openj9/normal/semeru"
    )
else
    # Adoptium Temurin GA / EA candidate sequence (covers standard, future, snapshot & obsolete versions)
    CANDIDATE_URLS+=(
        "https://api.adoptium.net/v3/binary/latest/${INPUT}/ga/linux/${ARCH}/jre/hotspot/normal/eclipse"
        "https://api.adoptium.net/v3/binary/latest/${INPUT}/ga/linux/${ARCH}/jdk/hotspot/normal/eclipse"
        "https://api.adoptium.net/v3/binary/latest/${INPUT}/ea/linux/${ARCH}/jre/hotspot/normal/eclipse"
        "https://api.adoptium.net/v3/binary/latest/${INPUT}/ea/linux/${ARCH}/jdk/hotspot/normal/eclipse"
    )
fi

DOWNLOADED=0
ARCHIVE_TYPE="tar"

for url in "${CANDIDATE_URLS[@]}"; do
    if curl -fsSL --retry 2 --connect-timeout 15 -A "MultiMinecraftEgg-JavaInstaller/1.0" -o "${TMP_ARCHIVE}" "${url}" 2>/dev/null; then
        if gzip -t "${TMP_ARCHIVE}" 2>/dev/null; then
            DOWNLOADED=1
            ARCHIVE_TYPE="tar"
            break
        elif unzip -t "${TMP_ARCHIVE}" >/dev/null 2>&1; then
            DOWNLOADED=1
            ARCHIVE_TYPE="zip"
            break
        elif tar -tf "${TMP_ARCHIVE}" >/dev/null 2>&1; then
            DOWNLOADED=1
            ARCHIVE_TYPE="tar_plain"
            break
        else
            rm -f "${TMP_ARCHIVE}"
        fi
    fi
done

if [ "${DOWNLOADED}" -ne 1 ]; then
    echo "ERROR: Could not find or download Java runtime for '${INPUT}' (${ARCH})." >&2
    exit 1
fi

mkdir -p "${TARGET_DIR}"

if [ "${ARCHIVE_TYPE}" = "tar" ]; then
    tar -xzf "${TMP_ARCHIVE}" -C "${TARGET_DIR}"
elif [ "${ARCHIVE_TYPE}" = "tar_plain" ]; then
    tar -xf "${TMP_ARCHIVE}" -C "${TARGET_DIR}"
elif [ "${ARCHIVE_TYPE}" = "zip" ]; then
    unzip -q -o "${TMP_ARCHIVE}" -d "${TARGET_DIR}"
fi

# Normalize directory if archive contained an outer wrapper folder
if [ ! -x "${TARGET_DIR}/bin/java" ]; then
    sub=$(find "${TARGET_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n1)
    if [ -n "${sub}" ] && [ -x "${sub}/bin/java" ]; then
        mv "${sub}"/* "${TARGET_DIR}/" 2>/dev/null || true
        mv "${sub}"/.[!.]* "${TARGET_DIR}/" 2>/dev/null || true
        rmdir "${sub}" 2>/dev/null || true
    fi
fi

chmod +x "${TARGET_DIR}/bin/"* 2>/dev/null || true

if [ -x "${TARGET_DIR}/bin/java" ]; then
    echo "Successfully installed Java (${TARGET_NAME}):"
    "${TARGET_DIR}/bin/java" -version 2>&1 | head -n 1
else
    echo "ERROR: Extraction finished but no executable bin/java found in ${TARGET_DIR}." >&2
    exit 1
fi