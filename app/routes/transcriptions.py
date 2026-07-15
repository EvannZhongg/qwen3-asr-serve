"""ASR routes (mounted when MODE in {asr, both}).

- POST /v1/audio/transcriptions       OpenAI-compatible single file
- POST /v1/audio/transcriptions/batch Multi-file extension
"""

from __future__ import annotations

import logging
import time
from typing import List, Optional

from fastapi import APIRouter, File, Form, HTTPException, Request, Response, UploadFile
from fastapi.responses import JSONResponse, PlainTextResponse

from app.audio_io import audio_duration_seconds, decode_audio_path, resolve_audio, resolve_audio_batch
from app.mapping import asr_to_openai, to_qwen_lang
from app.metrics import AUDIO_S_TOTAL, BATCH_SIZE_HIST, track
from app.schemas import BatchTranscriptionResponse, TranscriptionResponse


router = APIRouter(prefix="/v1/audio", tags=["asr"])
logger = logging.getLogger("qwen3-asr-serve.transcriptions")


_VALID_GRANULARITIES = {"word", "segment"}


def _ms(start: float) -> float:
    return (time.perf_counter() - start) * 1000.0


def _timing_headers(timings_ms: dict[str, float]) -> dict[str, str]:
    return {
        f"X-Qwen-Timing-{name}-Ms": f"{value:.3f}"
        for name, value in timings_ms.items()
    }


def _set_timing_headers(response: Response, timings_ms: dict[str, float]) -> None:
    for key, value in _timing_headers(timings_ms).items():
        response.headers[key] = value


def _decode_audio_paths(paths: List[str]) -> list[tuple]:
    return [decode_audio_path(path) for path in paths]


def _normalize_granularities(values: Optional[List[str]]) -> List[str]:
    if not values:
        return []
    out: List[str] = []
    for v in values:
        v = (v or "").strip().lower()
        if not v:
            continue
        if v not in _VALID_GRANULARITIES:
            raise HTTPException(
                status_code=400,
                detail=f"unsupported timestamp_granularity: {v!r}; "
                       f"valid: {sorted(_VALID_GRANULARITIES)}",
            )
        out.append(v)
    return out


def _check_ts_supported(request: Request, granularities: List[str]) -> None:
    if granularities and request.app.state.mode == "asr":
        raise HTTPException(
            status_code=400,
            detail=(
                "timestamp_granularities[] requires the forced aligner; this "
                "server was started with MODE=asr. Restart with MODE=both."
            ),
        )


@router.post(
    "/transcriptions",
    response_model=TranscriptionResponse,
    responses={200: {"content": {"text/plain": {}}}},
)
async def transcribe(
    request: Request,
    file: Optional[UploadFile] = File(None, description="Audio file (multipart)."),
    file_path: Optional[str] = Form(None, description="Local file path (when ALLOW_LOCAL_PATHS=true)."),
    model: str = Form("qwen3-asr-1.7b"),
    language: Optional[str] = Form(None, description="ISO 639-1 code, e.g. 'zh','en'. Omit for auto-detect."),
    response_format: str = Form("json", description="json | verbose_json | text"),
    timestamp_granularities: List[str] = Form(default_factory=list, alias="timestamp_granularities[]"),
):
    """OpenAI-compatible /v1/audio/transcriptions.

    File-path input is the fast path — set ALLOW_LOCAL_PATHS=true and pass `file_path`
    instead of uploading via multipart.
    """
    if response_format not in {"json", "verbose_json", "text"}:
        raise HTTPException(status_code=400, detail=f"unsupported response_format: {response_format}")

    granularities = _normalize_granularities(timestamp_granularities)
    _check_ts_supported(request, granularities)

    total_start = time.perf_counter()
    qwen_lang = to_qwen_lang(language)
    resolve_start = time.perf_counter()
    audio = await resolve_audio(file, file_path)
    resolve_ms = _ms(resolve_start)

    inference_start = 0.0
    inference_ms = 0.0
    metrics_start = 0.0
    metrics_ms = 0.0
    async with track("transcriptions", request.app.state.mode):
        metrics_start = time.perf_counter()
        AUDIO_S_TOTAL.labels(route="transcriptions").inc(audio_duration_seconds(audio))
        BATCH_SIZE_HIST.labels(route="transcriptions").observe(1)
        metrics_ms = _ms(metrics_start)
        inference_start = time.perf_counter()
        results = request.app.state.asr.transcribe(
            audio=[audio],
            language=qwen_lang,
            return_time_stamps=bool(granularities),
        )
        inference_ms = _ms(inference_start)
    mapping_start = time.perf_counter()
    payload = asr_to_openai(results[0], granularities, response_format)
    mapping_ms = _ms(mapping_start)
    timings = {
        "Resolve": resolve_ms,
        "Metrics": metrics_ms,
        "Inference": inference_ms,
        "Mapping": mapping_ms,
        "Total": _ms(total_start),
    }

    if isinstance(payload, PlainTextResponse):
        _set_timing_headers(payload, timings)
        return payload
    return JSONResponse(payload, headers=_timing_headers(timings))


@router.post("/transcriptions/batch", response_model=BatchTranscriptionResponse)
async def transcribe_batch(
    request: Request,
    response: Response,
    audio_files: List[UploadFile] = File(default_factory=list),
    file_paths: List[str] = Form(default_factory=list),
    model: str = Form("qwen3-asr-1.7b"),
    language: Optional[str] = Form(None),
    response_format: str = Form("json"),
    timestamp_granularities: List[str] = Form(default_factory=list, alias="timestamp_granularities[]"),
) -> BatchTranscriptionResponse:
    """Batch transcription: one inference call across many audios.

    Pass `audio_files[]` (multipart) OR `file_paths[]` (paths). Results
    preserve input order.
    """
    if response_format not in {"json", "verbose_json", "text"}:
        raise HTTPException(status_code=400, detail=f"unsupported response_format: {response_format}")
    if response_format == "text":
        # batch + plain text would require concatenation semantics we don't define
        raise HTTPException(status_code=400, detail="response_format=text not supported on /batch")

    granularities = _normalize_granularities(timestamp_granularities)
    _check_ts_supported(request, granularities)

    total_start = time.perf_counter()
    qwen_lang = to_qwen_lang(language)
    resolve_start = time.perf_counter()
    audios = await resolve_audio_batch(audio_files, file_paths)
    resolve_ms = _ms(resolve_start)

    metrics_start = 0.0
    metrics_ms = 0.0
    inference_start = 0.0
    inference_ms = 0.0
    async with track("transcriptions_batch", request.app.state.mode):
        metrics_start = time.perf_counter()
        total_dur = sum(audio_duration_seconds(a) for a in audios)
        AUDIO_S_TOTAL.labels(route="transcriptions_batch").inc(total_dur)
        BATCH_SIZE_HIST.labels(route="transcriptions_batch").observe(len(audios))
        metrics_ms = _ms(metrics_start)
        inference_start = time.perf_counter()
        results = request.app.state.asr.transcribe(
            audio=audios,
            language=qwen_lang,
            return_time_stamps=bool(granularities),
        )
        inference_ms = _ms(inference_start)

    mapping_start = time.perf_counter()
    mapped_results = [asr_to_openai(r, granularities, response_format) for r in results]
    mapping_ms = _ms(mapping_start)
    _set_timing_headers(response, {
        "Resolve": resolve_ms,
        "Metrics": metrics_ms,
        "Inference": inference_ms,
        "Mapping": mapping_ms,
        "Total": _ms(total_start),
    })
    return BatchTranscriptionResponse(
        results=mapped_results
    )


@router.post("/transcriptions/batch_predecoded", response_model=BatchTranscriptionResponse)
async def transcribe_batch_predecoded(
    request: Request,
    response: Response,
    file_paths: List[str] = Form(...),
    model: str = Form("qwen3-asr-1.7b"),
    language: Optional[str] = Form(None),
    response_format: str = Form("json"),
    timestamp_granularities: List[str] = Form(default_factory=list, alias="timestamp_granularities[]"),
) -> BatchTranscriptionResponse:
    """Internal benchmark route: validate paths, predecode to ndarray, then transcribe.

    This isolates qwen_asr path-input overhead from ndarray-input inference.
    """
    if response_format not in {"json", "verbose_json"}:
        raise HTTPException(status_code=400, detail=f"unsupported response_format: {response_format}")

    granularities = _normalize_granularities(timestamp_granularities)
    _check_ts_supported(request, granularities)

    total_start = time.perf_counter()
    qwen_lang = to_qwen_lang(language)

    resolve_start = time.perf_counter()
    resolved_paths = await resolve_audio_batch(None, file_paths)
    resolve_ms = _ms(resolve_start)
    path_inputs = [p for p in resolved_paths if isinstance(p, str)]

    decode_start = time.perf_counter()
    audios = _decode_audio_paths(path_inputs)
    decode_ms = _ms(decode_start)

    async with track("transcriptions_batch_predecoded", request.app.state.mode):
        metrics_start = time.perf_counter()
        total_dur = sum(audio_duration_seconds(a) for a in audios)
        AUDIO_S_TOTAL.labels(route="transcriptions_batch_predecoded").inc(total_dur)
        BATCH_SIZE_HIST.labels(route="transcriptions_batch_predecoded").observe(len(audios))
        metrics_ms = _ms(metrics_start)

        inference_start = time.perf_counter()
        results = request.app.state.asr.transcribe(
            audio=audios,
            language=qwen_lang,
            return_time_stamps=bool(granularities),
        )
        inference_ms = _ms(inference_start)

    mapping_start = time.perf_counter()
    mapped_results = [asr_to_openai(r, granularities, response_format) for r in results]
    mapping_ms = _ms(mapping_start)
    _set_timing_headers(response, {
        "Resolve": resolve_ms,
        "Decode": decode_ms,
        "Metrics": metrics_ms,
        "Inference": inference_ms,
        "Mapping": mapping_ms,
        "Total": _ms(total_start),
    })
    return BatchTranscriptionResponse(results=mapped_results)
