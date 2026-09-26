"""
Tests for the fallback chain (llm.py). No network: providers are replaced with
fakes, and error classification is tested on real error bodies.

Run from backend/:  venv/Scripts/python.exe -m pytest
"""

import time
from datetime import datetime

import pytest

import llm
from classifier import Classification
from llm import CallFailed, ModelRef, Outcome

A = ModelRef("gemini", "primary")
B = ModelRef("gemini", "second")
C = ModelRef("groq", "third")

# The real 429 body Gemini returned in production when the daily quota ran out
# (trimmed). Note retryDelay says 11s even though the quota only resets at
# midnight Pacific -- the reason quotaId, not retryDelay, decides the outcome.
GEMINI_DAILY_QUOTA_429 = {"error": {
    "code": 429,
    "message": "You exceeded your current quota, please check your plan and billing details.",
    "status": "RESOURCE_EXHAUSTED",
    "details": [
        {"@type": "type.googleapis.com/google.rpc.Help", "links": []},
        {"@type": "type.googleapis.com/google.rpc.QuotaFailure", "violations": [{
            "quotaMetric": "generativelanguage.googleapis.com/generate_content_free_tier_requests",
            "quotaId": "GenerateRequestsPerDayPerProjectPerModel-FreeTier",
            "quotaDimensions": {"location": "global", "model": "gemini-3.6-flash"},
            "quotaValue": "20",
        }]},
        {"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "11s"},
    ],
}}

GEMINI_PER_MINUTE_429 = {"error": {
    "code": 429, "message": "Quota exceeded.", "status": "RESOURCE_EXHAUSTED",
    "details": [
        {"@type": "type.googleapis.com/google.rpc.QuotaFailure", "violations": [
            {"quotaId": "GenerateRequestsPerMinutePerProjectPerModel-FreeTier"}]},
        {"@type": "type.googleapis.com/google.rpc.RetryInfo", "retryDelay": "7.5s"},
    ],
}}

VALID_JSON = '{"title": "Deadlift", "summary": "A strength exercise.", "category": "Fitness & Health", "folder": "Gym"}'
BAD_CATEGORY_JSON = '{"title": "Deadlift", "summary": "A strength exercise.", "category": "Gym Stuff", "folder": "Gym"}'


@pytest.fixture(autouse=True)
def isolated(monkeypatch):
    llm.reset_state()
    sleeps = []
    monkeypatch.setattr(llm, "_sleep", sleeps.append)  # record waits, don't wait
    yield sleeps
    llm.reset_state()


def fake_providers(monkeypatch, behaviour: dict[str, list]):
    """behaviour: model name -> list of results to return in order
    (str = response text, CallFailed = raised). Returns the call log."""
    calls = []

    def call(ref, prompt, schema, temperature, timeout_s):
        calls.append(ref.name)
        result = behaviour[ref.name].pop(0)
        if isinstance(result, Exception):
            raise result
        return result

    monkeypatch.setattr(llm, "_PROVIDERS", {"gemini": call, "groq": call})
    return calls


# --- error classification --------------------------------------------------

def test_gemini_daily_quota_is_detected_despite_short_retry_delay():
    now = time.time()
    f = llm.classify_gemini_error(429, GEMINI_DAILY_QUOTA_429, now)
    assert f.outcome is Outcome.QUOTA_EXHAUSTED
    # Blocked until the next midnight Pacific -- not for the advertised 11 s.
    reset = datetime.fromtimestamp(f.blocked_until, llm.PACIFIC)
    assert f.blocked_until > now + 11
    assert (reset.hour, reset.minute, reset.second) == (0, 0, 0)


def test_gemini_per_minute_limit_is_a_short_wait():
    f = llm.classify_gemini_error(429, GEMINI_PER_MINUTE_429, time.time())
    assert f.outcome is Outcome.RATE_LIMITED
    assert f.retry_after == 7.5


@pytest.mark.parametrize("code, outcome", [
    (500, Outcome.UNAVAILABLE), (503, Outcome.UNAVAILABLE), (408, Outcome.UNAVAILABLE),
    (404, Outcome.UNUSABLE), (403, Outcome.UNUSABLE), (401, Outcome.UNUSABLE),
    (400, Outcome.BAD_REQUEST),
])
def test_gemini_status_codes(code, outcome):
    assert llm.classify_gemini_error(code, {"error": {"message": "x"}}, time.time()).outcome is outcome


def test_groq_daily_limit_uses_its_retry_after():
    body = {"error": {"message": "Rate limit reached for model on requests per day (RPD): Limit 1000"}}
    f = llm.classify_groq_error(429, body, {"retry-after": "120"}, 1000.0)
    assert f.outcome is Outcome.QUOTA_EXHAUSTED
    assert f.blocked_until == 1120.0


def test_groq_per_minute_limit():
    body = {"error": {"message": "Rate limit reached on tokens per minute (TPM)"}}
    f = llm.classify_groq_error(429, body, {"retry-after": "3"}, 0.0)
    assert f.outcome is Outcome.RATE_LIMITED and f.retry_after == 3.0


def test_groq_schema_rejection_is_invalid_output_not_bad_request():
    body = {"error": {"message": "Generated JSON does not match the schema", "code": "json_validate_failed"}}
    assert llm.classify_groq_error(400, body, {}, 0.0).outcome is Outcome.INVALID_OUTPUT


@pytest.mark.parametrize("raw, seconds", [
    ("11.797239244s", 11.797239244), ("7s", 7.0), ("1m26.5s", 86.5), ("30", 30.0),
    (None, None), ("", None), ("soon", None),
])
def test_parse_seconds(raw, seconds):
    assert llm._parse_seconds(raw) == seconds


# --- the chain -------------------------------------------------------------

def test_daily_quota_skips_to_next_model_and_is_remembered(monkeypatch):
    quota = llm.classify_gemini_error(429, GEMINI_DAILY_QUOTA_429, time.time())
    calls = fake_providers(monkeypatch, {"primary": [quota], "second": [VALID_JSON, VALID_JSON]})

    first = llm.generate_json("t", "p", Classification, [A, B], budget_s=60)
    second = llm.generate_json("t", "p", Classification, [A, B], budget_s=60)

    assert first.model == "gemini:second" and first.value.category == "Fitness & Health"
    assert second.model == "gemini:second"
    assert calls == ["primary", "second", "second"]  # primary NOT called the second time
    assert not llm.is_available(A)


def test_bad_request_stops_the_chain(monkeypatch):
    calls = fake_providers(monkeypatch, {"primary": [CallFailed(Outcome.BAD_REQUEST, "bad")],
                                         "second": [VALID_JSON]})
    assert llm.generate_json("t", "p", Classification, [A, B], budget_s=60) is None
    assert calls == ["primary"]


def test_output_failing_the_schema_moves_to_next_model(monkeypatch):
    calls = fake_providers(monkeypatch, {"primary": [BAD_CATEGORY_JSON], "second": [VALID_JSON]})
    result = llm.generate_json("t", "p", Classification, [A, B], budget_s=60)
    assert result.model == "gemini:second"
    assert calls == ["primary", "second"]
    assert llm.is_available(A)  # a bad answer isn't a reason to block the model


def test_transient_error_is_retried_once_then_falls_back(monkeypatch, isolated):
    down = CallFailed(Outcome.UNAVAILABLE, "503")
    calls = fake_providers(monkeypatch, {"primary": [down, down], "third": ["answer"]})
    result = llm.generate_text("t", "p", [A, C], budget_s=60)
    assert result.value == "answer" and result.model == "groq:third"
    assert calls == ["primary", "primary", "third"]
    assert isolated == [2.0]  # one short pause before the single retry


def test_timeout_moves_on_without_retrying_the_slow_model(monkeypatch, isolated):
    slow = CallFailed(Outcome.UNAVAILABLE, "ReadTimeout", retry_same_model=False)
    calls = fake_providers(monkeypatch, {"primary": [slow], "second": ["fast answer"]})
    result = llm.generate_text("t", "p", [A, B], budget_s=25, attempt_timeout_s=15)
    assert result.model == "gemini:second"
    assert calls == ["primary", "second"] and isolated == []


def test_rate_limit_retry_waits_the_advertised_time(monkeypatch, isolated):
    limited = CallFailed(Outcome.RATE_LIMITED, "rpm", retry_after=4.0)
    calls = fake_providers(monkeypatch, {"primary": [limited, VALID_JSON]})
    result = llm.generate_json("t", "p", Classification, [A], budget_s=60)
    assert result.model == "gemini:primary"
    assert calls == ["primary", "primary"] and isolated == [4.0]


def test_long_rate_limit_goes_straight_to_next_model(monkeypatch, isolated):
    limited = CallFailed(Outcome.RATE_LIMITED, "rpm", retry_after=45.0)
    calls = fake_providers(monkeypatch, {"primary": [limited], "second": [VALID_JSON]})
    llm.generate_json("t", "p", Classification, [A, B], budget_s=60)
    assert calls == ["primary", "second"] and isolated == []


def test_time_budget_is_shared_across_the_chain(monkeypatch):
    clock = [0.0]
    monkeypatch.setattr(llm, "_now", lambda: clock[0])

    def slow_failure(ref, prompt, schema, temperature, timeout_s):
        clock[0] += timeout_s  # each attempt uses its whole timeout, then fails
        raise CallFailed(Outcome.INVALID_OUTPUT, "empty")

    monkeypatch.setattr(llm, "_PROVIDERS", {"gemini": slow_failure, "groq": slow_failure})
    started = clock[0]
    assert llm.generate_text("t", "p", [A, B, C], budget_s=25, attempt_timeout_s=15) is None
    # 15 s on A, then only 10 s left for B, then < 3 s left: C is never started.
    assert clock[0] - started == 25


def test_hard_deadline_abandons_a_stalled_call(monkeypatch):
    monkeypatch.setattr(llm, "ATTEMPT_GRACE_S", 0.0)

    def stalled(ref, prompt, schema, temperature, timeout_s):
        if ref.name == "primary":
            time.sleep(timeout_s + 0.5)  # ignores its own timeout, like the 43.5 s call
            return "too late"
        return "fast answer"

    monkeypatch.setattr(llm, "_PROVIDERS", {"gemini": stalled, "groq": stalled})
    started = time.monotonic()
    result = llm.generate_text("t", "p", [A, C], budget_s=10, attempt_timeout_s=0.2)
    assert result.model == "groq:third" and result.value == "fast answer"
    assert time.monotonic() - started < 3  # didn't wait for the stalled call


def test_unusable_model_is_skipped_afterwards(monkeypatch):
    calls = fake_providers(monkeypatch, {"primary": [CallFailed(Outcome.UNUSABLE, "404")],
                                         "second": ["a", "b"]})
    llm.generate_text("t", "p", [A, B], budget_s=60)
    llm.generate_text("t", "p", [A, B], budget_s=60)
    assert calls == ["primary", "second", "second"]


def test_all_models_failing_returns_none(monkeypatch):
    fake_providers(monkeypatch, {"primary": [""], "second": [""]})
    assert llm.generate_text("t", "p", [A, B], budget_s=60) is None


def test_unexpected_adapter_bug_does_not_raise(monkeypatch):
    def broken(*args):
        raise KeyError("bug")

    monkeypatch.setattr(llm, "_PROVIDERS", {"gemini": broken, "groq": broken})
    assert llm.generate_text("t", "p", [A], budget_s=60) is None


# --- configuration ---------------------------------------------------------

def test_chain_from_env_drops_groq_without_key_and_ignores_bad_entries(monkeypatch):
    monkeypatch.setenv("TEST_CHAIN", "gemini:one, nonsense ,groq:two,gemini:three")
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    assert [str(r) for r in llm.chain_from_env("TEST_CHAIN", "gemini:default")] == [
        "gemini:one", "gemini:three"]


def test_chain_from_env_keeps_groq_with_key(monkeypatch):
    monkeypatch.setenv("TEST_CHAIN", "gemini:one,groq:two")
    monkeypatch.setenv("GROQ_API_KEY", "x")
    assert [str(r) for r in llm.chain_from_env("TEST_CHAIN", "gemini:default")] == [
        "gemini:one", "groq:two"]
