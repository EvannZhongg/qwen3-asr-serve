#!/usr/bin/env bash
# Build-time installer for Docker runtime helper scripts.
# Manual-only Docker flow: install the optional helper entrypoint, but do not
# install conda activate.d/profile hooks and do not configure any autostart.
# The target platform overrides Docker CMD; start ASR explicitly with ./run.sh.
set -euo pipefail

APP_HOME="${APP_HOME:-/usr/local/app}"
CONDA_HOME="${CONDA_HOME:-/usr/local/app/miniforge3}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-qwen3-asr-flow}"
APP_DIR="${APP_HOME}/qwen3-asr-serve"

# Resolve from this script location instead of relying on current working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_script() {
    local src="$1"
    local dst="$2"
    cp "${src}" "${dst}"
    chmod a+rx "${dst}"
}

install_script "${SCRIPT_DIR}/start-qwen3-asr.sh" /usr/local/bin/start-qwen3-asr
bash -n /usr/local/bin/start-qwen3-asr

cat <<MSG
[install_runtime_scripts] installed /usr/local/bin/start-qwen3-asr
[install_runtime_scripts] skipped conda activate.d/profile autostart hooks
[install_runtime_scripts] manual start: cd ${APP_DIR} && ./run.sh
MSG

# Historical alternatives kept for reference only:
# 1) conda activate.d autostart hook:
#    install_script "${SCRIPT_DIR}/99-qwen3-asr-autostart.sh" \
#      "${CONDA_HOME}/envs/${CONDA_ENV_NAME}/etc/conda/activate.d/99-qwen3-asr-autostart.sh"
#
# 2) /etc/profile.d login-shell autostart:
#    install_script "${SCRIPT_DIR}/profile-autostart-qwen3-asr.sh" /etc/profile.d/qwen3-asr-autostart.sh
#
# 3) Older separate autostart wrapper:
#    install_script "${SCRIPT_DIR}/autostart-qwen3-asr.sh" /usr/local/bin/autostart-qwen3-asr
