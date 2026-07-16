#!/usr/bin/env bash
# Simplified conda activate.d autostart hook for Docker/platform images.
# When the packaged conda env is activated, start the ASR service in the
# background via the repository's own ./run.sh -d.  This keeps one service
# control path instead of maintaining a separate autostart wrapper.

if [ "${QWEN3_ASR_STARTING:-}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

if [ "${QWEN3_ASR_DISABLE_AUTOSTART:-}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

APP_HOME="${APP_HOME:-/usr/local/app}"
APP_DIR="${APP_HOME}/qwen3-asr-serve"
PID_FILE="${APP_DIR}/var/server.pid"
LOG_FILE="${APP_DIR}/logs/autostart.log"
LOCK_DIR="${APP_DIR}/var/conda-activate-autostart.lock"

[ -d "${APP_DIR}" ] || return 0 2>/dev/null || exit 0
mkdir -p "${APP_DIR}/var" "${APP_DIR}/logs"

# Fast path: if run.sh already has a live pid, do nothing.
if [ -f "${PID_FILE}" ]; then
    old_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [ -n "${old_pid}" ] && kill -0 "${old_pid}" 2>/dev/null; then
        return 0 2>/dev/null || exit 0
    fi
fi

# Avoid multiple concurrent conda activations racing to start the same service.
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    return 0 2>/dev/null || exit 0
fi

(
    cleanup() {
        rmdir "${LOCK_DIR}" 2>/dev/null || true
    }
    trap cleanup EXIT

    cd "${APP_DIR}" || exit 0
    echo "[conda-activate-autostart] starting qwen3-asr via ./run.sh -d" >> "${LOG_FILE}"
    bash ./run.sh -d >> "${LOG_FILE}" 2>&1 || true
) >/dev/null 2>&1 &

return 0 2>/dev/null || exit 0
