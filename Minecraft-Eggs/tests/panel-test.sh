#!/usr/bin/env bash
# Panel-behavior test suite for Multi Minecraft.
# Simulates the daemon lifecycle: start, stop (SIGTERM), kill (SIGKILL),
# restart, console-text stop (pipe + Feather-style TTY), stray sweep,
# crash diagnostics, theme output, panel detection and watcher modes.
set -u
cd "$(dirname "$0")/.."

# Git Bash on Windows mangles POSIX paths in command args - disable that.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

# Per-run unique suffix so parallel runs / shared Docker daemons never touch
# (or destroy) resources they do not own.
RUN_TAG="$$_$(date +%s)"
IMG="mc-eggs-test-${RUN_TAG}"
VOL="mc-test-ws-${RUN_TAG}"
C1="mc-t1-${RUN_TAG}"
C5C="mc-t5c-${RUN_TAG}"
C12="mc-t12-${RUN_TAG}"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

CREATED_CONTAINERS=""
track() { # remember every container this run created for exact cleanup
    CREATED_CONTAINERS="${CREATED_CONTAINERS:-} $1"
}

cleanup() {
    for c in ${CREATED_CONTAINERS:-}; do
        docker rm -f "${c}" >/dev/null 2>&1
    done
    docker volume rm -f "$VOL" >/dev/null 2>&1
    docker image rm -f "$IMG" >/dev/null 2>&1
}
trap cleanup EXIT

echo "== building test image =="
if ! docker build -q -t "$IMG" -f tests/Dockerfile.test . >/dev/null 2>&1; then
    echo "docker build failed:"; docker build -t "$IMG" -f tests/Dockerfile.test . | tail -20; exit 1
fi
echo "  image ready"

# ---------------------------------------------------------------- T1: START
echo "== T1: start (panel env, custom server) =="
track "$C1"
docker run -d --name "${C1}" -v "$VOL:/home/container" \
    -e P_SERVER_UUID=11111111-2222-3333-4444-555555555555 \
    -e SERVER_PORT=25565 -e SERVER_MEMORY=2048 -e AUTO_UPDATE_EGG=0 \
    -e SERVER_TYPE=custom \
    -e CUSTOM_COMMAND="python3 -u fake-server.py 25565" "$IMG" >/dev/null
booted=0
for i in $(seq 1 60); do
    docker logs ${C1} 2>&1 | grep -q "TEST-SERVER-UP port 25565" && { booted=1; break; }
    sleep 1
done
[ "$booted" = "1" ] && ok "server booted and serving on 25565" || { bad "server never booted"; docker logs ${C1} 2>&1 | tail -50; }
docker logs ${C1} 2>&1 | grep -q "Pelican Panel" && ok "panel family detected (Pelican via P_SERVER_UUID)" || { bad "panel detection"; docker logs ${C1} 2>&1 | grep -i "panel=" | head -3; }
docker logs ${C1} 2>&1 | grep -q "multi-minecraft" && ok "agent theme active" || bad "theme prefix"
docker logs ${C1} 2>&1 | grep -q "Universal Minecraft Server Runtime" && ok "banner tagline present" || bad "banner tagline"
docker logs ${C1} 2>&1 | grep -qE "gradient: (citrus|aurora|sunset|ocean|candy|spectrum|none)" && ok "gradient banner rendered" || bad "banner gradient line"
docker exec ${C1} curl -s "http://127.0.0.1:25565/" 2>/dev/null | grep -q "Directory listing" \
    && ok "HTTP 200 response" || bad "HTTP not responding"
docker exec ${C1} grep -q "Multi Minecraft boot @" /home/container/.logs/console.log 2>/dev/null \
    && ok "console mirror .logs/console.log active" || bad "console mirror missing"
docker exec ${C1} grep -q "boot @" /home/container/.logs/console.log 2>/dev/null \
    && ok "boot header in mirror" || bad "boot header missing"
docker logs ${C1} 2>&1 | grep -q "Server UUID" && ok "boot card shows server UUID" || bad "boot card UUID row"
docker logs ${C1} 2>&1 | grep "Server Type" | grep -q "custom" && ok "card shows server type" || bad "card server type"
docker logs ${C1} 2>&1 | grep "Stop Watcher" | grep -q "Enabled" && ok "card shows Stop Watcher enabled" || bad "card Stop Watcher"
docker exec ${C1} grep -q "launch:" /home/container/.logs/launcher-errors.log 2>/dev/null \
    && ok "launch marker in .logs/launcher-errors.log" || { bad "error journal missing launch entry"; docker exec ${C1} ls -la /home/container/.logs/ 2>&1 | head -5; }

# ---------------------------------------------------------------- T2: STOP
echo "== T2: stop from panel (SIGTERM to PID 1) =="
t0=$(date +%s)
docker stop -t 25 ${C1} >/dev/null
t1=$(date +%s); elapsed=$((t1-t0))
[ "$elapsed" -lt 20 ] && ok "graceful stop in ${elapsed}s (<20s, inside daemon force-kill window)" || bad "stop took ${elapsed}s"
docker logs ${C1} 2>&1 | grep -q "initiating graceful shutdown" && ok "shutdown log line present" || bad "no shutdown log"
docker logs ${C1} 2>&1 | grep -q "Server stopped gracefully" && ok "clean stop confirmation" || bad "no clean-stop confirmation"

# ---------------------------------------------------------------- T3: RESTART
echo "== T3: restart from panel =="
docker start ${C1} >/dev/null
restarted=0
for i in $(seq 1 60); do
    docker logs --since 90s ${C1} 2>&1 | grep -q "TEST-SERVER-UP port 25565" && { restarted=1; break; }
    sleep 1
done
[ "$restarted" = "1" ] && ok "server restarted and serving again" || bad "restart failed"
http_ok=0
for i in $(seq 1 30); do
    docker exec ${C1} curl -s "http://127.0.0.1:25565/" 2>/dev/null | grep -q "Directory listing" && { http_ok=1; break; }
    sleep 1
done
[ "${http_ok:-0}" = "1" ] && ok "HTTP responds after restart" || bad "HTTP down after restart"
docker exec ${C1} test -f /home/container/.logs/console.log.1 2>/dev/null \
    && ok "previous boot mirror rotated to console.log.1" || bad "mirror rotation"

# ---------------------------------------------------------------- T4: KILL
echo "== T4: kill from panel (SIGKILL) =="
docker kill ${C1} >/dev/null 2>&1
code=$(docker inspect -f '{{.State.ExitCode}}' ${C1} 2>/dev/null)
[ "$code" = "137" ] && ok "SIGKILL exit code 137" || bad "kill exit code was ${code}"

# ------------------------------------------------------- T5: CONSOLE-TEXT STOP
echo "== T5: stop via console text (pipe stdin daemon) =="
out=$( (sleep 14; echo stop) | timeout 60 docker run -i --rm \
    -e SERVER_PORT=25566 -e AUTO_UPDATE_EGG=0 -e SERVER_TYPE=custom \
    -e CUSTOM_COMMAND="python3 -u fake-server.py 25566" -v "$VOL:/home/container" "$IMG" 2>&1 )
rc=$?
[ "$rc" = "0" ] && ok "pipe text-stop exited 0" || bad "pipe text-stop exit code ${rc}"
echo "$out" | grep -q "Stop command 'stop' received via console" \
    && ok "watcher caught console stop text" || bad "watcher missed stop text"
echo "$out" | grep -q "stopped gracefully" && ok "text-stop ended cleanly (exit 0)" || bad "text-stop exit"
echo "$out" | grep -q "TEST-SERVER-UP port 25566" && ok "server was serving before text-stop" || bad "server never served in T5"

# ------------------------------------------- T5b: FEATHER-STYLE TTY TEXT STOP
echo "== T5b: stop via '^C' text on a TTY stdin (Feather Panel style) =="
tty_out=$(timeout 280 docker run -i --rm \
    -e SERVER_PORT=25572 -e AUTO_UPDATE_EGG=0 -e SERVER_TYPE=custom \
    -e CUSTOM_COMMAND="python3 -u fake-server.py 25572" -e TTY_READY_MATCH="TEST-SERVER-UP" \
    -v "$VOL:/home/container" "$IMG" \
    python3 /opt/potenfyr/t5b-driver.py 2>&1)
echo "$tty_out" | grep -aq "Stop command '\^C' received via console" \
    && ok "watcher caught '^C' text on TTY stdin" || { bad "watcher missed '^C' on tty"; echo "$tty_out" | tail -25; }
echo "$tty_out" | grep -aq "stopped gracefully" && ok "tty text-stop ended cleanly (exit 0)" || bad "tty text-stop exit"
echo "$tty_out" | grep -aq "TEST-SERVER-UP" && ok "server was serving before tty stop" || bad "server never served in T5b"

# ---------------------------------------------------- T5c: SIGNAL STOP (SIGINT)
echo "== T5c: stop via SIGINT signal to PID 1 (daemon ContainerKill branch) =="
track "$C5C"
docker run -d --name "${C5C}" -e SERVER_PORT=25573 -e AUTO_UPDATE_EGG=0 \
    -e SERVER_TYPE=custom -e CUSTOM_COMMAND="python3 -u -m http.server 25573" "$IMG" >/dev/null
sig_booted=0
for i in $(seq 1 60); do
    docker logs ${C5C} 2>&1 | grep -q "Serving HTTP" && { sig_booted=1; break; }
    sleep 1
done
[ "$sig_booted" = "1" ] && ok "server booted before signal stop" || bad "server never booted before signal stop"
docker kill --signal=SIGINT ${C5C} >/dev/null 2>&1
sig_stopped=0
for i in $(seq 1 30); do
    state=$(docker inspect -f '{{.State.Running}}' ${C5C} 2>/dev/null)
    [ "$state" = "false" ] && { sig_stopped=1; break; }
    sleep 1
done
[ "$sig_stopped" = "1" ] && ok "SIGINT to PID 1 stopped the container" || bad "container survived SIGINT"
[ "$(docker inspect -f '{{.State.ExitCode}}' ${C5C} 2>/dev/null)" = "0" ] \
    && ok "SIGINT stop exit code 0" || bad "SIGINT stop exit code not 0"
docker logs ${C5C} 2>&1 | grep -q "initiating graceful shutdown" && ok "trap logged SIGINT shutdown" || bad "no shutdown log on SIGINT"
docker logs ${C5C} 2>&1 | grep -q "stopped gracefully" && ok "clean confirmation after SIGINT" || bad "no clean-stop confirmation"

# --------------------------------------------------- T6: MULTI-PROCESS (pm2-ish)
echo "== T6: multi-process container (detached daemon + main server) =="
mp_out=$( (sleep 18; echo stop) | timeout 60 docker run -i --rm \
    -e SERVER_PORT=25591 -e AUTO_UPDATE_EGG=0 -e SERVER_TYPE=custom \
    -e CUSTOM_COMMAND="nohup python3 -u -m http.server 25590 >/dev/null 2>&1 & sleep 1; python3 -u -m http.server 25591" "$IMG" 2>&1 )
echo "$mp_out" | grep -q "Serving HTTP on 0.0.0.0 port 25591" && ok "main server booted" || { bad "main server never booted"; echo "$mp_out" | tail -20; }
echo "$mp_out" | grep -q "stopped gracefully" && ok "clean stop with detached daemon present" || bad "stop not clean with daemon"
echo "$mp_out" | grep -qE "Swept [0-9]+ stray process" && ok "stray daemon swept on stop" || { bad "no stray sweep log"; echo "$mp_out" | grep -iE "sweep|stray" | head -3; }

# ---------------------------------------------------------------- T7: CRASH
echo "== T7: crash diagnostics + error journal =="
crash_out=$(timeout 90 docker run --rm \
    -e SERVER_PORT=25567 -e AUTO_UPDATE_EGG=0 -e SERVER_TYPE=custom \
    -e CUSTOM_COMMAND="python3 -c 'import sys; print(\"about to die\"); sys.exit(2)'" "$IMG" 2>&1)
echo "$crash_out" | grep -q "CRASH DETECTED" && ok "crash report box printed" || bad "no crash report"
echo "$crash_out" | grep -q "launcher-errors.log" && ok "error-journal pointer shown" || bad "no journal pointer"
echo "$crash_out" | grep -q "last 12 console lines" && ok "recent-output tail in report" || bad "no output tail"

# ------------------------------------------------- T12: FEATHER PANEL DETECTION
echo "== T12: Feather Panel detection (P_SERVER_UUID + P_SERVER_UUID_SHORT) =="
track "$C12"
docker run -d --name "${C12}" \
    -e P_SERVER_UUID=530617d9-f5fa-411b-9fea-d2cf3c6286d4 -e P_SERVER_UUID_SHORT=530617d9 \
    -e SERVER_PORT=25574 -e AUTO_UPDATE_EGG=0 -e SERVER_TYPE=custom \
    -e CUSTOM_COMMAND="python3 -u -m http.server 25574" "$IMG" >/dev/null
fw_seen=0
card_seen=0
for i in $(seq 1 60); do
    docker logs ${C12} 2>&1 | grep -q "panel=Feather Panel" && fw_seen=1
    docker logs ${C12} 2>&1 | grep "Host Platform" | grep -q "Feather Panel" && { card_seen=1; break; }
    sleep 1
done
[ "$fw_seen" = "1" ] && ok "Feather Panel detected via P_SERVER_UUID_SHORT" || { bad "panel detection (Feather)"; docker logs ${C12} 2>&1 | grep -i "panel=" | head -3; }
[ "$card_seen" = "1" ] && ok "boot card shows Host Platform: Feather Panel" || { bad "card Host Platform"; docker logs ${C12} 2>&1 | grep -a "Host Platform" | head -2; }

# --------------------------------------------- T13: PANEL_STOP_WATCHER=0
echo "== T13: PANEL_STOP_WATCHER=0 passthrough mode =="
pw_out=$( (sleep 16; echo stop) | timeout 60 docker run -i --rm \
    -e SERVER_PORT=25583 -e AUTO_UPDATE_EGG=0 -e SERVER_TYPE=custom \
    -e CUSTOM_COMMAND="python3 -u -m http.server 25583" -e PANEL_STOP_WATCHER=0 "$IMG" 2>&1 )
echo "$pw_out" | grep -q "Stop command" && bad "watcher ran despite PANEL_STOP_WATCHER=0" || ok "watcher disabled (stop text not consumed)"
echo "$pw_out" | grep -q "Serving HTTP" && ok "server served in watcher-disabled mode" || bad "server never served (watcher disabled)"

# ------------------------------------------------ T14: CONSOLE FORWARDING
echo "== T14: non-stop console lines are forwarded to the server console =="
fw_out=$( (sleep 12; echo "whitelist add Herobrine"; sleep 2; echo stop) | timeout 90 docker run -i --rm \
    -e SERVER_PORT=25584 -e AUTO_UPDATE_EGG=0 -e SERVER_TYPE=custom \
    -e CUSTOM_COMMAND="python3 -u fake-server.py 25584" -v "$VOL:/home/container" "$IMG" 2>&1 )
echo "$fw_out" | grep -q "CONSOLE-ECHO:whitelist add Herobrine" \
    && ok "non-stop console line forwarded to server stdin" || bad "forwarded console line lost"
echo "$fw_out" | grep -q "Stop command 'stop' received via console" \
    && ok "stop command still caught after forwarded lines" || bad "watcher broke after forwarding"

echo
echo "=========================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" = "0" ]
