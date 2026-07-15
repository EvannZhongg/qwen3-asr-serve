#!/usr/bin/env bash
# Background autostart wrapper for Docker/platform images.
# Called by the conda activate.d hook; it avoids duplicate starts via pid,
# port, and lock checks, then launches /usr/local/bin/start-qwen3-asr detached.
set -e

export APP_HOME="${APP_HOME:-/usr/local/app}"

APP_DIR="${APP_HOME}/qwen3-asr-serve"
PID_FILE="${APP_DIR}/var/qwen3-asr-autostart.pid"
LOG_FILE="${APP_DIR}/logs/autostart.log"
LOCK_DIR="${APP_DIR}/var/qwen3-asr-autostart.lock"

mkdir -p "${APP_DIR}/var" "${APP_DIR}/logs"

if [ -f "${APP_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "${APP_DIR}/.env"
    set +a
fi
export ASR_PORT="${ASR_PORT:-${PORT:-9123}}"

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    echo "[autostart] another autostart is running, skip" >> "${LOG_FILE}"
    exit 0
fi

cleanup() {
    rmdir "${LOCK_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

if [ -f "${PID_FILE}" ]; then
    old_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [ -n "${old_pid}" ] && kill -0 "${old_pid}" 2>/dev/null; then
        echo "[autostart] qwen3-asr already running, pid=${old_pid}" >> "${LOG_FILE}"
        exit 0
    fi
fi

if [ -f "${APP_DIR}/var/server.pid" ]; then
    server_pid="$(cat "${APP_DIR}/var/server.pid" 2>/dev/null || true)"
    if [ -n "${server_pid}" ] && kill -0 "${server_pid}" 2>/dev/null; then
        echo "[autostart] run.sh server already running, pid=${server_pid}" >> "${LOG_FILE}"
        echo "${server_pid}" > "${PID_FILE}"
        exit 0
    fi
fi

if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | awk "{print \$4}" | grep -q ":${ASR_PORT}$"; then
        echo "[autostart] port ${ASR_PORT} already listening, skip" >> "${LOG_FILE}"
        exit 0
    fi
fi

echo "[autostart] starting qwen3-asr on port ${ASR_PORT}" >> "${LOG_FILE}"

START_CMD="echo \$\$ > \"${PID_FILE}\"; export QWEN3_ASR_FROM_AUTOSTART=1; exec /usr/local/bin/start-qwen3-asr"

if command -v setsid >/dev/null 2>&1; then
    setsid -f bash -lc "${START_CMD}" >> "${LOG_FILE}" 2>&1 < /dev/null
else
    coproc QWEN3_ASR_COPROC {
        bash -lc "${START_CMD}" >> "${LOG_FILE}" 2>&1 < /dev/null
    }
fi

sleep 1
new_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"

if [ -n "${new_pid}" ]; then
    echo "[autostart] started pid=${new_pid}" >> "${LOG_FILE}"
else
    echo "[autostart] started but pid unknown" >> "${LOG_FILE}"
fi

exit 0
