#!/usr/bin/env bash
# Build-time installer for Docker runtime helper scripts.
# Copies repository-maintained scripts into /usr/local/bin and conda
# activate.d directories, avoiding large heredoc/base64 script bodies in the
# Dockerfile.
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
install_script "${SCRIPT_DIR}/autostart-qwen3-asr.sh" /usr/local/bin/autostart-qwen3-asr

for env_dir in \
    /data/miniconda3/envs/env-3.8.8 \
    "${CONDA_HOME}/envs/${CONDA_ENV_NAME}"
do
    if [ -d "${env_dir}" ]; then
        mkdir -p "${env_dir}/etc/conda/activate.d"
        install_script \
            "${SCRIPT_DIR}/99-qwen3-asr-autostart.sh" \
            "${env_dir}/etc/conda/activate.d/99-qwen3-asr-autostart.sh"
    fi
done

bash -n /usr/local/bin/start-qwen3-asr
bash -n /usr/local/bin/autostart-qwen3-asr
bash -n "${SCRIPT_DIR}/99-qwen3-asr-autostart.sh"

# 构建期校验：平台 Dockerfile 自动改写/注入不能污染运行时脚本。
if grep -nE '^[[:space:]]*(USER|RUN)[[:space:]]' /usr/local/bin/autostart-qwen3-asr; then
    echo "ERROR: autostart script contains Dockerfile instructions"
    exit 1
fi

nl -ba /usr/local/bin/autostart-qwen3-asr | sed -n '45,90p'
