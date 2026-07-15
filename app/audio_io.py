"""Audio input resolver: multipart UploadFile  OR  local file path.

Returns the AudioLike type that `qwen_asr` understands directly — either:
  - `str` (treated as a local path / URL / base64) → upstream loads it
  - `(np.ndarray, sample_rate)` tuple

The "pass a path" branch is the fast path: no multipart upload, no temp file,
no double-decode. qwen_asr.inference.utils.normalize_audio_input handles
str→ndarray internally with mono+16k resampling.
"""

from __future__ import annotations

import io
import os
from functools import lru_cache
from typing import List, Optional, Tuple, Union

import numpy as np
import soundfile as sf
from fastapi import HTTPException, UploadFile

from app.config import settings


AudioLike = Union[str, Tuple[np.ndarray, int]]


@lru_cache(maxsize=65536)
def _cached_audio_duration_seconds(real_path: str, size: int, mtime_ns: int) -> float:
    """Cache soundfile metadata by path plus file identity fields."""
    try:
        info = sf.info(real_path)
        return float(info.duration)
    except Exception:  # noqa: BLE001
        return 0.0


def _allowed_real_prefixes(prefixes: str) -> Tuple[str, ...]:
    return tuple(os.path.realpath(p).rstrip("/") for p in prefixes.split(",") if p.strip())


def _validate_local_path_uncached(path: str, allow_local_paths: bool, allowed_path_prefixes: str) -> str:
    """Resolve to a real path and enforce ALLOWED_PATH_PREFIXES whitelist."""
    if not allow_local_paths:
        raise HTTPException(
            status_code=400,
            detail="local-path input is disabled (set ALLOW_LOCAL_PATHS=true to enable)",
        )
    allowed_prefixes = _allowed_real_prefixes(allowed_path_prefixes)
    if not allowed_prefixes:
        raise HTTPException(
            status_code=403,
            detail="ALLOWED_PATH_PREFIXES is empty; no local path is permitted",
        )

    try:
        real = os.path.realpath(path)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"invalid path: {e}") from e

    if not os.path.isfile(real):
        raise HTTPException(status_code=404, detail=f"not a file: {real}")

    for prefix in allowed_prefixes:
        if real.startswith(prefix + "/") or real == prefix:
            return real

    raise HTTPException(
        status_code=403,
        detail=f"path {real} is outside ALLOWED_PATH_PREFIXES",
    )


@lru_cache(maxsize=65536)
def _validate_local_path_cached(path: str, allow_local_paths: bool, allowed_path_prefixes: str) -> str:
    return _validate_local_path_uncached(path, allow_local_paths, allowed_path_prefixes)


def _validate_local_path(path: str) -> str:
    if settings.cache_local_path_validation:
        return _validate_local_path_cached(
            path,
            settings.allow_local_paths,
            settings.allowed_path_prefixes,
        )
    return _validate_local_path_uncached(
        path,
        settings.allow_local_paths,
        settings.allowed_path_prefixes,
    )


async def _read_multipart(file: UploadFile) -> Tuple[np.ndarray, int]:
    """Decode an uploaded audio file in-memory to (waveform, sr)."""
    data = await file.read()
    if len(data) > settings.max_file_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"file too large: {len(data)} > MAX_FILE_BYTES={settings.max_file_bytes}",
        )
    try:
        wav, sr = sf.read(io.BytesIO(data), dtype="float32", always_2d=False)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"audio decode failed: {e}") from e
    if wav.ndim > 1:
        wav = wav.mean(axis=1)
    return wav.astype(np.float32, copy=False), int(sr)


def decode_audio_path(path: str) -> Tuple[np.ndarray, int]:
    """Decode a validated local path to the same ndarray form as multipart input."""
    try:
        wav, sr = sf.read(path, dtype="float32", always_2d=False)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=400, detail=f"audio decode failed: {e}") from e
    if wav.ndim > 1:
        wav = wav.mean(axis=1)
    return wav.astype(np.float32, copy=False), int(sr)


async def resolve_audio(
    file: Optional[UploadFile],
    file_path: Optional[str],
) -> AudioLike:
    """Pick the right input form. Raise 400 if neither / both are provided."""
    if (file is None or file.filename in (None, "")) and not file_path:
        raise HTTPException(
            status_code=400,
            detail="provide exactly one of `file` or `file_path`",
        )
    if file_path and file is not None and getattr(file, "filename", None):
        raise HTTPException(
            status_code=400,
            detail="provide only one of `file` or `file_path`",
        )

    if file_path:
        return _validate_local_path(file_path)
    return await _read_multipart(file)  # type: ignore[arg-type]


async def resolve_audio_batch(
    audio_files: Optional[List[UploadFile]],
    file_paths: Optional[List[str]],
) -> List[AudioLike]:
    """Batch variant. Exactly one of the two lists must be non-empty."""
    has_uploads = bool(audio_files) and any(f.filename for f in audio_files)
    has_paths = bool(file_paths)
    if has_uploads == has_paths:  # both empty or both filled
        raise HTTPException(
            status_code=400,
            detail="provide exactly one of `audio_files[]` or `file_paths[]`",
        )

    if has_paths:
        return [_validate_local_path(p) for p in file_paths]
    out: List[AudioLike] = []
    for f in audio_files:  # type: ignore[union-attr]
        out.append(await _read_multipart(f))
    return out


def audio_duration_seconds(audio: AudioLike) -> float:
    """Best-effort duration probe (used by metrics).  Path input → soundfile.info."""
    if not settings.enable_audio_duration_metrics:
        return 0.0
    if isinstance(audio, str):
        try:
            st = os.stat(audio)
            return _cached_audio_duration_seconds(
                os.path.realpath(audio),
                int(st.st_size),
                int(st.st_mtime_ns),
            )
        except Exception:  # noqa: BLE001
            return 0.0
    wav, sr = audio
    if sr <= 0:
        return 0.0
    return float(len(wav) / sr)
