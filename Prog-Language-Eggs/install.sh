#!/bin/bash
# =============================================================================
#  Multi-Language Eggs - Container Installation Script
#  By PotenFYR Studios (https://github.com/PotenFYR-Studios/Prog-Language-Eggs)
#
#  Multi-Panel Support:
#    - Pterodactyl Panel (/mnt/server)
#    - Pelican Panel (/mnt/server)
#    - Feather Panel (/app or /mnt/server)
#    - PufferPanel (/server)
#    - Standalone Docker / Kubernetes ($PWD)
# =============================================================================

set -uo pipefail

# Determine install mount directory across all panel types
INSTALL_DIR="/mnt/server"
if [ ! -d "${INSTALL_DIR}" ]; then
    if [ -d "/server" ]; then
        INSTALL_DIR="/server"
    elif [ -d "/app" ]; then
        INSTALL_DIR="/app"
    else
        INSTALL_DIR="${PWD}"
    fi
fi

cd "${INSTALL_DIR}" 2>/dev/null || { mkdir -p "${INSTALL_DIR}" && cd "${INSTALL_DIR}"; }

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

DEBUG="${DEBUG:-0}"
[ "${DEBUG}" = "1" ] && set -x

GIT_REPO="${GIT_REPO:-}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_AUTH_TOKEN="${GIT_AUTH_TOKEN:-}"
STARTER_TEMPLATE="${STARTER_TEMPLATE:-}"
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-1}"
EXTRA_URLS="${EXTRA_URLS:-}"
USER_AGENT="ProgLanguageEggsInstall/1.0 (PotenFYR Studios; support@potenfyr.in)"

# -----------------------------------------------------------------------------
# 1. Git Repository Clone
# -----------------------------------------------------------------------------
# Same rules as the launcher's sync_git_repo: trim panel-supplied values,
# re-point origin at the current repo/token, fetch the configured branch and
# reset to FETCH_HEAD (origin/<branch> is stale on single-branch clones and
# branch switches), surface token-redacted errors, and fetch OVER an existing
# non-empty workspace instead of failing the clone. Never wipes user files.
if [ -n "${GIT_REPO}" ]; then
    GIT_REPO="$(printf '%s' "${GIT_REPO}" | tr -d ' \t\r\n')"
    GIT_BRANCH="$(printf '%s' "${GIT_BRANCH:-main}" | tr -d ' \t\r\n')"
    [ -n "${GIT_BRANCH}" ] || GIT_BRANCH="main"
    GIT_AUTH_TOKEN="$(printf '%s' "${GIT_AUTH_TOKEN:-}" | tr -d ' \t\r\n')"
    export GIT_TERMINAL_PROMPT=0
    export GIT_ASKPASS=/bin/true
    redact_err_git() { tr '\n' ' ' < "$1" | sed -e "s#${GIT_AUTH_TOKEN}#***#g" | cut -c1-300; }

    _err="$(mktemp 2>/dev/null || echo "/tmp/potenfyr-git-$$")"
    log "Syncing source code from Git repository: ${GIT_REPO} (branch: ${GIT_BRANCH})..."

    AUTH_REPO_URL="${GIT_REPO}"
    if [ -n "${GIT_AUTH_TOKEN}" ]; then
        if [[ "${GIT_REPO}" =~ ^https:// ]]; then
            AUTH_REPO_URL="https://${GIT_AUTH_TOKEN}@${GIT_REPO#https://}"
        fi
    fi

    if [ -d ".git" ]; then
        log "Updating existing Git repository..."
        git remote set-url origin "${AUTH_REPO_URL}" 2>/dev/null || git remote add origin "${AUTH_REPO_URL}" 2>/dev/null || true
        if git fetch --depth 1 origin "${GIT_BRANCH}" 2>"${_err}"; then
            git reset --hard FETCH_HEAD 2>"${_err}" || warn "Could not apply fetched commits: $(redact_err_git "${_err}")"
        else
            warn "Git fetch failed: $(redact_err_git "${_err}")"
        fi
    elif find . -mindepth 1 -maxdepth 1 2>/dev/null | grep -q .; then
        log "Workspace already has files - fetching repository over them (no wipe)..."
        git init -q . 2>/dev/null || true
        git remote remove origin 2>/dev/null || true
        if git remote add origin "${AUTH_REPO_URL}" 2>"${_err}" && git fetch --depth 1 origin "${GIT_BRANCH}" 2>"${_err}"; then
            git reset --hard FETCH_HEAD 2>"${_err}" || warn "Could not apply fetched commits"
        else
            warn "Git fetch failed - existing files kept: $(redact_err_git "${_err}")"
        fi
    else
        if ! git clone --branch "${GIT_BRANCH}" --depth 1 "${AUTH_REPO_URL}" . 2>"${_err}"; then
            warn "Cloning branch ${GIT_BRANCH} failed: $(redact_err_git "${_err}"). Attempting default clone..."
            git clone --depth 1 "${AUTH_REPO_URL}" . 2>"${_err}" || warn "Git clone failed: $(redact_err_git "${_err}")"
        fi
    fi
    if _head="$(git rev-parse --short HEAD 2>/dev/null)"; then
        ok "Repository at commit ${_head}"
    fi
    rm -f "${_err}" 2>/dev/null || true
    unset _err _head
    ok "Git repository initialized"
fi

# -----------------------------------------------------------------------------
# 2. Starter Template Scaffolding
# -----------------------------------------------------------------------------
FILE_COUNT=$(find . -maxdepth 1 -not -name '.*' 2>/dev/null | wc -l)
if [ "${FILE_COUNT}" -eq 0 ] && [ -n "${STARTER_TEMPLATE}" ] && [ "${STARTER_TEMPLATE}" != "empty" ]; then
    log "Generating starter template: '${STARTER_TEMPLATE}'..."
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
            ;;
    esac
    ok "Starter template generated"
fi

# -----------------------------------------------------------------------------
# 3. Extra URL Downloads
# -----------------------------------------------------------------------------
if [ -n "${EXTRA_URLS}" ]; then
    log "Downloading additional files from EXTRA_URLS..."
    IFS=$'\n'
    for line in ${EXTRA_URLS}; do
        [ -z "${line}" ] && continue
        dest=""
        url="${line}"
        case "${line}" in
            *\|*)
                dest="${line%%|*}"
                url="${line#*|}"
                ;;
        esac
        
        filename=$(basename "${url}" | sed 's/[?].*//')
        target_path="${filename}"
        if [ -n "${dest}" ]; then
            mkdir -p "${dest}"
            target_path="${dest}/${filename}"
        fi
        
        log "Downloading: ${url} -> ${target_path}"
        if curl -fsSL --retry 2 --connect-timeout 20 -A "${USER_AGENT}" -o "${target_path}" "${url}"; then
            case "${filename}" in
                *.zip)
                    unzip -qo "${target_path}" -d "${dest:-.}"
                    rm -f "${target_path}"
                    ;;
                *.tar.gz|*.tgz)
                    tar -xzf "${target_path}" -C "${dest:-.}"
                    rm -f "${target_path}"
                    ;;
            esac
            ok "Saved ${target_path}"
        else
            warn "Failed to download ${url}"
        fi
    done
fi

# -----------------------------------------------------------------------------
# 4. Dependency Pre-Installation
# -----------------------------------------------------------------------------
if [ "${AUTO_INSTALL_DEPS}" = "1" ]; then
    log "Pre-installing dependencies..."
    if [ -f "package.json" ]; then
        if [ -f "bun.lockb" ] && command -v bun >/dev/null 2>&1; then
            bun install || true
        elif [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
            pnpm install || true
        elif [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
            yarn install || true
        else
            npm install --no-audit --no-fund 2>/dev/null || true
        fi
    fi
    if [ -f "requirements.txt" ]; then
        pip3 install -r requirements.txt 2>/dev/null || pip install -r requirements.txt || true
    fi
    if [ -f "go.mod" ]; then
        go mod download 2>/dev/null || true
    fi
    if [ -f "Cargo.toml" ]; then
        cargo fetch 2>/dev/null || true
    fi
    if [ -f "composer.json" ] && command -v composer >/dev/null 2>&1; then
        composer install --no-dev --optimize-autoloader || composer install || true
    fi
    ok "Dependencies pre-installed"
fi

# Ensure permissive directory permissions for any panel user ID
chmod -R 777 "${INSTALL_DIR}" 2>/dev/null || true

ok "Installation completed successfully on ${INSTALL_DIR}!"
