"""
Resilient text generation: run a prompt through an ordered chain of models
(e.g. primary Gemini -> second Gemini -> Groq) and return the first valid
answer, plus which model produced it.

Every generation call (classify, answer) goes through here. Embeddings do NOT:
vectors from different models can't be compared, so embeddings must never
fall back to another model (see docs/decisions.md, "AI fallback").

Three ideas carry the design (research notes in docs/decisions.md):
1. Decide by the CAUSE of an error, not just its status code. Gemini uses 429
   for both a per-minute limit (wait seconds) and an exhausted daily quota
   (wait until midnight Pacific) -- and its daily-quota 429 still says "retry
   in ~11s", so the retry delay can't tell them apart. The `quotaId` can.
2. Remember each model's state between requests (a tiny circuit breaker):
   an exhausted model is skipped instantly instead of being called again.
   Plain in-memory state is enough because the server runs one worker; after
   a restart the first call simply rediscovers it.
3. One time budget per action. Moving to the next model doesn't reset the
   clock, so a fallback can never make a slow path slower than the budget.

Contract (same as the rest of the AI code): never raises. All models failing
-> None, and the caller degrades as before.
"""

import logging
import os
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeout
from dataclasses import dataclass
from datetime import datetime, timedelta
from enum import Enum
from typing import Callable, Generic, TypeVar
from zoneinfo import ZoneInfo

import httpx
from dotenv import load_dotenv
from google.genai import errors as genai_errors
from google.genai import types
from pydantic import BaseModel, ValidationError

from gemini import get_client

load_dotenv()

log = logging.getLogger(__name__)

T = TypeVar("T")

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
PACIFIC = ZoneInfo("America/Los_Angeles")  # Gemini daily quotas reset at midnight Pacific

# One quick retry on the same model is allowed only when the wait is this
# short; longer waits go straight to the next model instead.
MAX_RETRY_WAIT_S = 10.0
# Don't start an attempt with less time than this left in the budget.
MIN_ATTEMPT_S = 3.0
# A model that fails this many times in a row (5xx/timeouts) is skipped for
# UNHEALTHY_COOLDOWN_S -- stops hammering a provider that's down.
UNHEALTHY_AFTER = 3
UNHEALTHY_COOLDOWN_S = 60.0
# HTTP timeouts limit each phase (connect, each read), not the whole call: a
# stalling server held one Gemini call for 43.5 s against a 30 s timeout. So
# every attempt also gets a hard deadline, enforced by running it in a worker
# thread and giving up on waiting. An abandoned call finishes in the
# background and its result is discarded.
ATTEMPT_GRACE_S = 1.0
_executor = ThreadPoolExecutor(max_workers=8, thread_name_prefix="llm")


class Outcome(Enum):
    RATE_LIMITED = "rate_limited"        # short limit (per minute): wait seconds
    QUOTA_EXHAUSTED = "quota_exhausted"  # daily quota gone: skip until it resets
    UNAVAILABLE = "unavailable"          # 5xx, overload, timeout, network: transient
    BAD_REQUEST = "bad_request"          # our request is wrong: no model will accept it
    UNUSABLE = "unusable"                # model gone (404) or key rejected (401/403)
    INVALID_OUTPUT = "invalid_output"    # answered, but empty / not matching the schema


@dataclass(frozen=True)
class ModelRef:
    provider: str  # "gemini" | "groq"
    name: str

    def __str__(self) -> str:
        return f"{self.provider}:{self.name}"

    @classmethod
    def parse(cls, spec: str) -> "ModelRef":
        provider, _, name = spec.strip().partition(":")
        if provider not in _PROVIDERS or not name:
            raise ValueError(f"invalid model spec {spec!r} (expected 'gemini:<model>' or 'groq:<model>')")
        return cls(provider, name)


@dataclass
class Result(Generic[T]):
    value: T
    model: str  # e.g. "gemini:gemini-3.6-flash" -- which model actually answered


class CallFailed(Exception):
    def __init__(self, outcome: Outcome, detail: str = "", retry_after: float | None = None,
                 blocked_until: float | None = None, retry_same_model: bool = True):
        super().__init__(f"{outcome.value}: {detail}")
        self.outcome = outcome
        self.detail = detail
        self.retry_after = retry_after      # seconds, for a quick retry on the same model
        self.blocked_until = blocked_until  # epoch seconds, for QUOTA_EXHAUSTED
        # False for timeouts: a model that was too slow will likely be too slow
        # again, and retrying it burned the whole answer budget in a live test
        # (15 s + 9 s on the same model, fallbacks never reached).
        self.retry_same_model = retry_same_model


# ---------------------------------------------------------------------------
# Configuration


def chain_from_env(var: str, default: str) -> list[ModelRef]:
    """Parse a chain like "gemini:gemini-3.6-flash,groq:openai/gpt-oss-120b".

    Lives in env vars so a model that disappears from a free tier is a config
    change in Railway, not a code change. Groq entries are dropped when
    GROQ_API_KEY isn't set, so the chain still works Gemini-only.
    """
    chain = []
    for spec in (os.environ.get(var) or default).split(","):
        if not spec.strip():
            continue
        try:
            ref = ModelRef.parse(spec)
        except ValueError as e:
            log.error("%s: %s -- entry ignored", var, e)
            continue
        if ref.provider == "groq" and not os.environ.get("GROQ_API_KEY"):
            log.info("%s: %s skipped (GROQ_API_KEY not set)", var, ref)
            continue
        chain.append(ref)
    if not chain:
        log.error("%s is empty after parsing; falling back to the default", var)
        return [ModelRef.parse(s) for s in default.split(",") if not s.startswith("groq:")]
    return chain


# ---------------------------------------------------------------------------
# Error classification (pure functions -- unit-tested in tests/test_llm.py)


def _next_pacific_midnight(now: float) -> float:
    local = datetime.fromtimestamp(now, PACIFIC)
    midnight = (local + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    return midnight.timestamp()


def _parse_seconds(value: str | None) -> float | None:
    """'11.797239244s' / '7s' / '1m26.5s' / '30' -> seconds."""
    if not value:
        return None
    m = re.fullmatch(r"\s*(?:(\d+)m)?\s*([\d.]+)?s?\s*", str(value))
    if not m or not any(m.groups()):
        return None
    return float(m.group(1) or 0) * 60 + float(m.group(2) or 0)


def classify_gemini_error(code: int, body: object, now: float) -> CallFailed:
    """Turn a Gemini API error (status + JSON body) into an outcome."""
    error = body.get("error", {}) if isinstance(body, dict) else {}
    message = str(error.get("message", ""))[:300]
    if code == 429:
        quota_ids, retry_after = [], None
        for detail in error.get("details") or []:
            kind = str(detail.get("@type", ""))
            if kind.endswith("QuotaFailure"):
                quota_ids += [str(v.get("quotaId", "")) for v in detail.get("violations") or []]
            elif kind.endswith("RetryInfo"):
                retry_after = _parse_seconds(detail.get("retryDelay"))
        if any("PerDay" in q for q in quota_ids):
            # retry_after deliberately ignored: for daily quotas it's still ~10s.
            return CallFailed(Outcome.QUOTA_EXHAUSTED, message, blocked_until=_next_pacific_midnight(now))
        return CallFailed(Outcome.RATE_LIMITED, message, retry_after=retry_after or 60.0)
    if code == 404:
        return CallFailed(Outcome.UNUSABLE, message)
    if code in (401, 403):
        return CallFailed(Outcome.UNUSABLE, message)
    if code == 408 or code >= 500:
        return CallFailed(Outcome.UNAVAILABLE, message)
    return CallFailed(Outcome.BAD_REQUEST, message)


def classify_groq_error(code: int, body: object, headers: dict, now: float) -> CallFailed:
    """Turn a Groq (OpenAI-compatible) error into an outcome."""
    error = body.get("error", {}) if isinstance(body, dict) else {}
    message = str(error.get("message", ""))[:300]
    retry_after = _parse_seconds(headers.get("retry-after"))
    if code == 429:
        # Groq names the limit in the message ("... on requests per day (RPD) ...")
        # and its retry-after is the real time until capacity comes back.
        if "per day" in message.lower():
            return CallFailed(Outcome.QUOTA_EXHAUSTED, message,
                              blocked_until=now + (retry_after or 3600.0))
        return CallFailed(Outcome.RATE_LIMITED, message, retry_after=retry_after or 60.0)
    if code == 400 and error.get("code") == "json_validate_failed":
        # Groq's schema enforcement rejected the model's own output -- the
        # request was fine, the answer wasn't.
        return CallFailed(Outcome.INVALID_OUTPUT, message)
    if code in (401, 403, 404):
        return CallFailed(Outcome.UNUSABLE, message)
    if code in (408, 413) or code >= 500:
        # 413 = this request exceeds the free tier's tokens-per-minute cap;
        # another model may still take it.
        return CallFailed(Outcome.UNAVAILABLE, message)
    return CallFailed(Outcome.BAD_REQUEST, message)


# ---------------------------------------------------------------------------
# Provider adapters: prompt in -> raw text out, or CallFailed


def _call_gemini(ref: ModelRef, prompt: str, schema: type[BaseModel] | None,
                 temperature: float, timeout_s: float) -> str:
    config = types.GenerateContentConfig(
        temperature=temperature,
        automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
        # Retries happen in ONE place (the chain below); the SDK's own retries
        # would multiply attempts and delay on top of ours.
        http_options=types.HttpOptions(
            timeout=int(timeout_s * 1000),
            retry_options=types.HttpRetryOptions(attempts=1),
        ),
    )
    if schema is not None:
        config.response_mime_type = "application/json"
        config.response_schema = schema
    try:
        response = get_client().models.generate_content(model=ref.name, contents=prompt, config=config)
    except genai_errors.APIError as e:
        raise classify_gemini_error(e.code, e.details, time.time()) from e
    except httpx.TimeoutException as e:
        raise CallFailed(Outcome.UNAVAILABLE, f"{type(e).__name__}: {e}", retry_same_model=False) from e
    except httpx.HTTPError as e:  # connection errors
        raise CallFailed(Outcome.UNAVAILABLE, f"{type(e).__name__}: {e}") from e
    return response.text or ""


def _groq_schema(schema: type[BaseModel]) -> dict:
    # Strict mode requires every object to forbid extra properties.
    js = schema.model_json_schema()
    js["additionalProperties"] = False
    return {"name": schema.__name__, "strict": True, "schema": js}


def _call_groq(ref: ModelRef, prompt: str, schema: type[BaseModel] | None,
               temperature: float, timeout_s: float) -> str:
    payload = {
        "model": ref.name,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": temperature,
    }
    if schema is not None:
        payload["response_format"] = {"type": "json_schema", "json_schema": _groq_schema(schema)}
    try:
        resp = httpx.post(
            GROQ_URL,
            json=payload,
            headers={"Authorization": f"Bearer {os.environ.get('GROQ_API_KEY', '')}"},
            timeout=timeout_s,
        )
    except httpx.TimeoutException as e:
        raise CallFailed(Outcome.UNAVAILABLE, f"{type(e).__name__}: {e}", retry_same_model=False) from e
    except httpx.HTTPError as e:
        raise CallFailed(Outcome.UNAVAILABLE, f"{type(e).__name__}: {e}") from e
    if resp.status_code != 200:
        try:
            body = resp.json()
        except ValueError:
            body = {}
        raise classify_groq_error(resp.status_code, body, dict(resp.headers), time.time())
    try:
        return resp.json()["choices"][0]["message"]["content"] or ""
    except (ValueError, KeyError, IndexError, TypeError) as e:
        raise CallFailed(Outcome.INVALID_OUTPUT, f"unexpected response shape: {e!r}") from e


_PROVIDERS: dict[str, Callable[..., str]] = {"gemini": _call_gemini, "groq": _call_groq}

# Swappable in tests.
_now: Callable[[], float] = time.monotonic
_sleep: Callable[[float], None] = time.sleep


# ---------------------------------------------------------------------------
# Per-model state


@dataclass
class _ModelState:
    blocked_until: float = 0.0  # epoch seconds; skipped until then
    fail_streak: int = 0
    unusable: bool = False      # 404 / rejected key: skipped until the process restarts


_state: dict[str, _ModelState] = {}
_state_lock = threading.Lock()  # BackgroundTasks and requests run in a thread pool


def _st(ref: ModelRef) -> _ModelState:
    return _state.setdefault(str(ref), _ModelState())


def is_available(ref: ModelRef) -> bool:
    with _state_lock:
        s = _st(ref)
        return not s.unusable and time.time() >= s.blocked_until


def _record_failure(ref: ModelRef, f: CallFailed) -> None:
    with _state_lock:
        s = _st(ref)
        if f.outcome is Outcome.QUOTA_EXHAUSTED:
            s.blocked_until = f.blocked_until or time.time() + 3600
        elif f.outcome is Outcome.RATE_LIMITED:
            s.blocked_until = time.time() + (f.retry_after or 60.0)
        elif f.outcome is Outcome.UNUSABLE:
            s.unusable = True
        elif f.outcome is Outcome.UNAVAILABLE:
            s.fail_streak += 1
            if s.fail_streak >= UNHEALTHY_AFTER:
                s.blocked_until = time.time() + UNHEALTHY_COOLDOWN_S
                s.fail_streak = 0


def _record_success(ref: ModelRef) -> None:
    with _state_lock:
        s = _st(ref)
        s.fail_streak = 0
        s.blocked_until = 0.0


def reset_state() -> None:
    """Forget all model state (tests, or after fixing a key without a restart)."""
    with _state_lock:
        _state.clear()


# ---------------------------------------------------------------------------
# The chain


def _run(job: str, chain: list[ModelRef], attempt: Callable[[ModelRef, float], T],
         budget_s: float, attempt_timeout_s: float) -> Result[T] | None:
    deadline = _now() + budget_s
    for ref in chain:
        if not is_available(ref):
            log.info("llm %s: %s skipped (unavailable)", job, ref)
            continue
        retried = False
        while True:
            remaining = deadline - _now()
            if remaining < MIN_ATTEMPT_S:
                log.warning("llm %s: time budget of %.0fs used up", job, budget_s)
                return None
            started = _now()
            timeout_s = min(remaining, attempt_timeout_s)
            try:
                future = _executor.submit(attempt, ref, timeout_s)
                try:
                    value = future.result(timeout=timeout_s + ATTEMPT_GRACE_S)
                except FutureTimeout:
                    raise CallFailed(Outcome.UNAVAILABLE, f"no response within {timeout_s:.0f}s",
                                     retry_same_model=False) from None
            except CallFailed as f:
                _record_failure(ref, f)
                log.warning("llm %s: %s -> %s after %.1fs: %s",
                            job, ref, f.outcome.value, _now() - started, f.detail[:160])
                if f.outcome is Outcome.BAD_REQUEST:
                    return None  # the request itself is wrong; no model will accept it
                wait = f.retry_after if f.outcome is Outcome.RATE_LIMITED else 2.0
                if (not retried and f.retry_same_model
                        and f.outcome in (Outcome.RATE_LIMITED, Outcome.UNAVAILABLE)
                        and wait <= MAX_RETRY_WAIT_S and wait + MIN_ATTEMPT_S < deadline - _now()):
                    retried = True
                    _sleep(wait)
                    continue
                break  # next model
            except Exception:
                # A bug in an adapter must not break the "never raise" contract.
                log.exception("llm %s: %s failed unexpectedly", job, ref)
                break
            _record_success(ref)
            log.info("llm %s: served_by=%s in %.1fs", job, ref, _now() - started)
            return Result(value, str(ref))
    log.warning("llm %s: every model in the chain failed", job)
    return None


def generate_json(job: str, prompt: str, schema: type[BaseModel], chain: list[ModelRef],
                  budget_s: float, attempt_timeout_s: float = 30.0,
                  temperature: float = 0.2) -> Result[BaseModel] | None:
    """Structured output: the response must validate against `schema`.

    Validation is the quality gate for every provider: JSON that doesn't match
    (e.g. a category outside the fixed list) counts as a failure and moves on
    to the next model, even when the provider said "200 OK".
    """
    def attempt(ref: ModelRef, timeout_s: float) -> BaseModel:
        text = _PROVIDERS[ref.provider](ref, prompt, schema, temperature, timeout_s)
        try:
            return schema.model_validate_json(text)
        except ValidationError as e:
            raise CallFailed(Outcome.INVALID_OUTPUT, f"{e.error_count()} validation errors: {text[:120]!r}")

    return _run(job, chain, attempt, budget_s, attempt_timeout_s)


def generate_text(job: str, prompt: str, chain: list[ModelRef], budget_s: float,
                  attempt_timeout_s: float = 30.0, temperature: float = 0.3) -> Result[str] | None:
    """Free text; an empty answer counts as a failure."""
    def attempt(ref: ModelRef, timeout_s: float) -> str:
        text = _PROVIDERS[ref.provider](ref, prompt, None, temperature, timeout_s).strip()
        if not text:
            raise CallFailed(Outcome.INVALID_OUTPUT, "empty response")
        return text

    return _run(job, chain, attempt, budget_s, attempt_timeout_s)
