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

install_conda_hook() {
    local env_dir="$1"
    if [ -d "${env_dir}" ]; then
        local hook_dir="${env_dir}/etc/conda/activate.d"
        mkdir -p "${hook_dir}"
        install_script \
            "${SCRIPT_DIR}/99-qwen3-asr-autostart.sh" \
            "${hook_dir}/99-qwen3-asr-autostart.sh"
        bash -n "${hook_dir}/99-qwen3-asr-autostart.sh"
    fi
}

# 1) Service env: protects explicit `conda activate qwen3-asr-flow`.
install_conda_hook "${CONDA_HOME}/envs/${CONDA_ENV_NAME}"

# 2) Platform default env: bore's /data/bore_run_script/end.sh activates
# $ENV_DEFAULT_PYTHON from /data/miniconda3.  Installing the same lightweight
# hook here starts the service as soon as the platform enters the environment.
install_conda_hook "/data/miniconda3/envs/env-3.8.8"

# If the build environment exposes ENV_DEFAULT_PYTHON, support both name and
# absolute-path forms as an extra best-effort target.
if [ -n "${ENV_DEFAULT_PYTHON:-}" ]; then
    if [ -d "${ENV_DEFAULT_PYTHON}" ]; then
        install_conda_hook "${ENV_DEFAULT_PYTHON}"
    else
        install_conda_hook "/data/miniconda3/envs/${ENV_DEFAULT_PYTHON}"
    fi
fi

bash -n /usr/local/bin/start-qwen3-asr

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
