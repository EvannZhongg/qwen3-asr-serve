#!/usr/bin/env bash
# Conda activate.d hook for Docker/platform images.
# It is installed into selected conda envs and triggers the ASR autostart
# wrapper when the platform activates an environment.

if [ "${QWEN3_ASR_STARTING:-}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

if [ "${QWEN3_ASR_DISABLE_AUTOSTART:-}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

/usr/local/bin/autostart-qwen3-asr || true
