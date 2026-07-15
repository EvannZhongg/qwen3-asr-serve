#!/usr/bin/env bash
# Main Docker image entrypoint for qwen3-asr-serve.
# Activates the packaged conda environment, prepares runtime cache/log dirs,
# then delegates to repository run.sh so .env and normal service controls work.
set -e

export APP_HOME="${APP_HOME:-/usr/local/app}"
export CONDA_HOME="${CONDA_HOME:-/usr/local/app/miniforge3}"
export CONDA_ENV_NAME="${CONDA_ENV_NAME:-qwen3-asr-flow}"

# 避免 start-qwen3-asr 内部 conda activate 时递归触发 activate.d 自启动钩子
export QWEN3_ASR_STARTING=1

if [ -f "${CONDA_HOME}/etc/profile.d/conda.sh" ]; then
    source "${CONDA_HOME}/etc/profile.d/conda.sh"
    conda activate "${CONDA_ENV_NAME}"
fi

unset QWEN3_ASR_STARTING

export PATH="${CONDA_HOME}/envs/${CONDA_ENV_NAME}/bin:${CONDA_HOME}/bin:${PATH}"
export CONDA_PREFIX="${CONDA_HOME}/envs/${CONDA_ENV_NAME}"
export CONDA_DEFAULT_ENV="${CONDA_ENV_NAME}"
hash -r || true

export LD_LIBRARY_PATH="/usr/local/nvidia/lib:/usr/local/nvidia/lib64"
export HOME="${HOME:-/tmp}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/.cache}"
export HF_HOME="${HF_HOME:-/tmp/huggingface}"
export MODELSCOPE_CACHE="${MODELSCOPE_CACHE:-/tmp/modelscope}"
export TORCH_HOME="${TORCH_HOME:-/tmp/torch}"

mkdir -p "${APP_HOME}/qwen3-asr-serve/var" "${APP_HOME}/qwen3-asr-serve/logs" /tmp/.cache /tmp/huggingface /tmp/modelscope /tmp/torch

cd "${APP_HOME}/qwen3-asr-serve"

echo "[start-qwen3-asr] user=$(whoami)"
echo "[start-qwen3-asr] python=$(which python)"
echo "[start-qwen3-asr] uvicorn=$(which uvicorn)"
python -V
uvicorn --version || true
if [ -f .env ]; then
    echo "[start-qwen3-asr] using .env runtime config"
    grep -E '^(MODE|HOST|PORT|GPU_MEM_UTIL|ENABLE_AUDIO_DURATION_METRICS|CACHE_LOCAL_PATH_VALIDATION)=' .env || true
else
    echo "[start-qwen3-asr] .env not found; run.sh/app defaults will be used"
fi

exec bash run.sh "$@"
