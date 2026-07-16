#!/usr/bin/env bash
# Build-time installer for Docker runtime helper scripts.
# Minimal Docker flow: install the main entrypoint and a simplified conda
# activate.d hook.  The hook delegates to the repository's ./run.sh -d, so
# there is no separate autostart wrapper to maintain.
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

HOOK_DIR="${CONDA_HOME}/envs/${CONDA_ENV_NAME}/etc/conda/activate.d"
mkdir -p "${HOOK_DIR}"
install_script \
    "${SCRIPT_DIR}/99-qwen3-asr-autostart.sh" \
    "${HOOK_DIR}/99-qwen3-asr-autostart.sh"

bash -n /usr/local/bin/start-qwen3-asr
bash -n "${HOOK_DIR}/99-qwen3-asr-autostart.sh"

# Historical alternatives kept for reference only:
# 1) /etc/profile.d login-shell autostart:
#
# install_script "${SCRIPT_DIR}/profile-autostart-qwen3-asr.sh" /etc/profile.d/qwen3-asr-autostart.sh
#
# 2) Older separate autostart wrapper:
#
# install_script "${SCRIPT_DIR}/autostart-qwen3-asr.sh" /usr/local/bin/autostart-qwen3-asr
# bash -n /usr/local/bin/autostart-qwen3-asr
#
# # 构建期校验：平台 Dockerfile 自动改写/注入不能污染运行时脚本。
# if grep -nE '^[[:space:]]*(USER|RUN)[[:space:]]' /usr/local/bin/autostart-qwen3-asr; then
#     echo "ERROR: autostart script contains Dockerfile instructions"
#     exit 1
# fi
#
# nl -ba /usr/local/bin/autostart-qwen3-asr | sed -n '45,90p'
