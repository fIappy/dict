#!/usr/bin/env python3
"""Run the AI entry generator from plain Python, without the eval kernel.

Subagents in this session cannot use `eval` with `language: py`, so the shared
worker (`tool/ai_defs_kernel.py`) needs its two host helpers supplied from the
outside. This driver does that: it reads the harness provider from
`~/.omp/agent/models.yml`, exposes a synchronous `completion` / `wait` pair backed
by a thread pool, injects them into the worker module, and awaits the same
`generate_range` / `generate_singles` code paths. Validation, part files and
resume behaviour are therefore identical to the eval route.

    python tool/ai_defs_driver.py --start 10672 --count 600 --per 6 --conc 10

Provider: `--provider` (default custom-tianyuanks-net), overridable with
DICT_AI_BASE_URL / DICT_AI_API_KEY / DICT_AI_MODEL.
"""

import argparse
import asyncio
import concurrent.futures as cf
import os
import re
import sys
import threading
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tool"))
import ai_defs_kernel as K  # noqa: E402

MODELS_YML = Path.home() / ".omp" / "agent" / "models.yml"
SYSTEM_PROMPT = K.G.SYSTEM


def read_provider(path, name):
    """baseUrl + apiKey of one provider block in models.yml (no YAML dependency)."""
    if not path.is_file():
        return None, None
    base = key = None
    inside = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if re.match(rf"^  {re.escape(name)}:\s*$", line):
            inside = True
            continue
        if inside and re.match(r"^  \S", line):
            break
        if not inside:
            continue
        m = re.match(r"^    baseUrl:\s*(\S+)", line)
        if m:
            base = m.group(1)
        m = re.match(r"^    apiKey:\s*(\S+)", line)
        if m:
            key = m.group(1).strip("\"'")
    return base, key


class Provider:
    def __init__(self, base_url, api_key, model, workers):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model
        self.pool = cf.ThreadPoolExecutor(max_workers=workers)
        self.local = threading.local()
        self.dropped_format = False
        self.dropped_effort = False

    @property
    def session(self):
        session = getattr(self.local, "session", None)
        if session is None:
            session = self.local.session = requests.Session()
        return session

    def _once(self, prompt, system):
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system or SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.6,
            "max_tokens": 8192,
        }
        if not self.dropped_format:
            payload["response_format"] = {"type": "json_object"}
        if not self.dropped_effort:
            payload["reasoning_effort"] = "none"
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        resp = self.session.post(
            self.base_url + "/chat/completions",
            headers=headers,
            json=payload,
            timeout=300,
        )
        if resp.status_code == 400 and not self.dropped_format and "response_format" in resp.text:
            self.dropped_format = True
            return self._once(prompt, system)
        if resp.status_code == 400 and not self.dropped_effort and "reasoning_effort" in resp.text:
            self.dropped_effort = True
            return self._once(prompt, system)
        resp.raise_for_status()
        body = resp.json()
        choice = body["choices"][0]
        content = choice["message"].get("content") or ""
        if not content.strip():
            raise ValueError(f"empty content (finish={choice.get('finish_reason')})")
        return content

    def complete(self, prompt, system=None):
        last = None
        for attempt in range(1, 4):
            try:
                return self._once(prompt, system)
            except Exception as exc:  # noqa: BLE001 - retried, then surfaced
                last = exc
                if "429" in str(exc):
                    time.sleep(10 * attempt)
                else:
                    time.sleep(2 * attempt)
        raise last if last is not None else RuntimeError("completion failed")

    def submit(self, prompt, system=None):
        return self.pool.submit(self.complete, prompt, system)


def make_wait(raise_errors=True):
    def wait(handles, *args, **kwargs):
        errors = kwargs.pop("raise_errors", raise_errors)
        out = []
        for handle in handles:
            try:
                out.append(handle.result())
            except Exception as exc:  # noqa: BLE001 - slot keeps the failure
                if errors:
                    raise
                out.append(exc)
        return out

    return wait


async def run(args, provider):
    setattr(K, "completion", lambda prompt, system=None, **_kw: provider.submit(prompt, system))
    setattr(K, "wait", make_wait())
    res = await K.generate_range(args.start, args.count, args.per, args.conc, tag=args.tag)
    bad = res["bad"]
    if bad:
        left = await K.generate_singles(bad, tag=args.singles_tag, conc=max(2, args.conc // 2))
    else:
        left = []
    print(f"[driver] ok={res['ok']} bad={len(bad)} left={len(left)}")
    if left:
        print("still failing:", [item["word"] for item in left])
    return 0 if not left else 1


def main():
    ap = argparse.ArgumentParser(description="Generate AI learner entries via the harness provider.")
    ap.add_argument("--start", type=int, required=True)
    ap.add_argument("--count", type=int, default=600)
    ap.add_argument("--per", type=int, default=6)
    ap.add_argument("--conc", type=int, default=10)
    ap.add_argument("--tag", default=None)
    ap.add_argument("--singles-tag", default=None)
    ap.add_argument("--provider", default="custom-tianyuanks-net")
    ap.add_argument("--model", default=os.environ.get("DICT_AI_MODEL", "deepseek-flash"))
    ap.add_argument("--base-url", default=os.environ.get("DICT_AI_BASE_URL", ""))
    ap.add_argument("--api-key", default=os.environ.get("DICT_AI_API_KEY", ""))
    args = ap.parse_args()

    base, key = args.base_url, args.api_key
    if not base or not key:
        base_yml, key_yml = read_provider(MODELS_YML, args.provider)
        base = base or base_yml or ""
        key = key or key_yml or ""
    if not base:
        sys.exit(f"no endpoint: {MODELS_YML} has no {args.provider}.baseUrl and no DICT_AI_BASE_URL")

    tag = args.tag or f"d{args.start:06d}"
    args.tag = tag
    args.singles_tag = args.singles_tag or f"p{args.start:06d}"

    provider = Provider(base, key, args.model, max(args.conc, 4))
    print(f"[driver] {base} model={args.model} start={args.start} count={args.count} "
          f"per={args.per} conc={args.conc} tag={tag}", flush=True)
    sys.exit(asyncio.run(run(args, provider)))


if __name__ == "__main__":
    main()
