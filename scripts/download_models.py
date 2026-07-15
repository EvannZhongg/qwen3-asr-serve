"""Download Qwen3-ASR + ForcedAligner weights from ModelScope.

Usage:
    python scripts/download_models.py --mode {asr|aligner|both}

Models are written under ./models by default, e.g.:
    models/Qwen3-ASR-1.7B
    models/Qwen3-ForcedAligner-0.6B

Equivalent manual commands:
    pip install -U modelscope
    modelscope download --model Qwen/Qwen3-ASR-1.7B --local_dir ./models/Qwen3-ASR-1.7B
    modelscope download --model Qwen/Qwen3-ForcedAligner-0.6B --local_dir ./models/Qwen3-ForcedAligner-0.6B
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


ASR_MODEL = "Qwen/Qwen3-ASR-1.7B"
ALIGNER_MODEL = "Qwen/Qwen3-ForcedAligner-0.6B"
DEFAULT_MODEL_DIR = Path("./models")


def _model_name(model_id: str) -> str:
    return model_id.rstrip("/").split("/")[-1]


def _modelscope_cmd() -> list[str]:
    exe = shutil.which("modelscope")
    if exe:
        return [exe]
    raise RuntimeError(
        "modelscope CLI not found. Install it first with: pip install -U modelscope"
    )


def _download_modelscope(model_id: str, local_dir: Path) -> None:
    """Download one model through ModelScope CLI with resume behavior handled by CLI."""
    local_dir.mkdir(parents=True, exist_ok=True)
    cmd = _modelscope_cmd() + [
        "download",
        "--model",
        model_id,
        "--local_dir",
        str(local_dir),
    ]
    print(f"[download] {' '.join(cmd)}")
    subprocess.run(cmd, check=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mode", choices=["asr", "aligner", "both"], default="both")
    ap.add_argument("--model-dir", type=Path, default=DEFAULT_MODEL_DIR)
    ap.add_argument("--asr-model", default=ASR_MODEL)
    ap.add_argument("--aligner-model", default=ALIGNER_MODEL)
    args = ap.parse_args()

    try:
        if args.mode in ("asr", "both"):
            target = args.model_dir / _model_name(args.asr_model)
            print(f"[download] {args.asr_model} → {target}")
            _download_modelscope(args.asr_model, target)

        if args.mode in ("aligner", "both"):
            target = args.model_dir / _model_name(args.aligner_model)
            print(f"[download] {args.aligner_model} → {target}")
            _download_modelscope(args.aligner_model, target)
    except subprocess.CalledProcessError as e:
        print(f"[download] ModelScope command failed with exit code {e.returncode}", file=sys.stderr)
        return e.returncode
    except RuntimeError as e:
        print(f"[download] {e}", file=sys.stderr)
        return 127

    print("[download] done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
