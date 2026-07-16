#!/usr/bin/env bash
# Simple login-shell autostart hook for Docker/platform images.
# Installed to /etc/profile.d by install_runtime_scripts.sh.  When a user enters
# an interactive shell, it starts the service in the background via ./run.sh -d.
# Disable with: export QWEN3_ASR_DISABLE_AUTOSTART=1

# Only run for interactive shells; avoid surprising non-interactive scripts.
case "$-" in
    *i*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac

if [ "${QWEN3_ASR_DISABLE_AUTOSTART:-}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

APP_HOME="${APP_HOME:-/usr/local/app}"
CONDA_HOME="${CONDA_HOME:-/usr/local/app/miniforge3}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-qwen3-asr-flow}"
APP_DIR="${APP_HOME}/qwen3-asr-serve"
LOG_FILE="${APP_DIR}/logs/autostart.log"
LOCK_DIR="${APP_DIR}/var/profile-autostart.lock"
PID_FILE="${APP_DIR}/var/server.pid"

[ -d "${APP_DIR}" ] || return 0 2>/dev/null || exit 0
mkdir -p "${APP_DIR}/var" "${APP_DIR}/logs"

# Fast path: if run.sh already has a live pid, do nothing.
if [ -f "${PID_FILE}" ]; then
    old_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [ -n "${old_pid}" ] && kill -0 "${old_pid}" 2>/dev/null; then
        return 0 2>/dev/null || exit 0
    fi
fi

# Avoid multiple simultaneous SSH shells racing to start the same service.
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    return 0 2>/dev/null || exit 0
fi

(
    cleanup() {
        rmdir "${LOCK_DIR}" 2>/dev/null || true
    }
    trap cleanup EXIT

    cd "${APP_DIR}" || exit 0

    # Load .env so we can cheaply check the configured port before calling run.sh.
    if [ -f .env ]; then
        set -a
        # shellcheck disable=SC1091
        source .env
        set +a
    fi
    PORT="${PORT:-9123}"

    if command -v ss >/dev/null 2>&1; then
        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${PORT}$"; then
            echo "[profile-autostart] port ${PORT} already listening, skip" >> "${LOG_FILE}"
            exit 0
        fi
    fi

    # Make run.sh use the packaged conda env without needing `conda activate`.
    export PATH="${CONDA_HOME}/envs/${CONDA_ENV_NAME}/bin:${CONDA_HOME}/bin:${PATH}"
    export CONDA_PREFIX="${CONDA_HOME}/envs/${CONDA_ENV_NAME}"
    export CONDA_DEFAULT_ENV="${CONDA_ENV_NAME}"

    echo "[profile-autostart] starting qwen3-asr via ./run.sh -d" >> "${LOG_FILE}"
    bash ./run.sh -d >> "${LOG_FILE}" 2>&1 || true
) >/dev/null 2>&1 &

return 0 2>/dev/null || exit 0
