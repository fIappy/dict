#!/usr/bin/env python3
"""Regenerate the 48 English IPA demonstration clips in assets/audio/ipa/.

THIS IS THE FALLBACK PATH. The clips committed to this repo are cut from the
dictionary's own human recordings by `tool/generate_ipa_audio_from_mdd.dart`
(same voice as the word lookups). Use this script instead when the 1.7 GB .mdd
archive is not at hand -- it needs only espeak-ng and ffmpeg, but its output is
formant-synthesised and sounds mechanical.

Why a generator at all
----------------------
The first version of these assets was assembled by name-matching files from a
third-party repository. That silently produced the *wrong sounds*: the
monophthongs were **cardinal vowel** reference recordings, not English phonemes.
Cardinal [ʌ] is an open-mid **back** unrounded vowel; English /ʌ/ ("cup") is
central-ish [ɐ]. Cardinal [e] is close-mid front; English /e/ ("bed") is open-mid
[ɛ]. So the clip for /ʌ/ did not match what a chart such as Cambridge's plays,
which is precisely what was reported.

Synthesising from espeak-ng makes the phoneme identity a property of the build
instead of a property of somebody else's filename. The mapping is re-derived
from canonical words on every run.

espeak's own alphabet, not IPA
------------------------------
espeak-ng only accepts **its own phoneme mnemonics** inside `[[...]]`. Raw IPA
is parsed without complaint but renders as digital silence (-91 dBFS), so
`[[ʌ]]` yields an empty clip rather than an error. Every mnemonic below is
therefore verified against espeak's `-x` output for an anchor word.

Also note espeak appends a constant 301 ms of silence to every utterance and
applies its `-s` speed only to vowels, diphthongs and voiceless fricatives --
voiced sonorants come back at a fixed 27-98 ms no matter the speed. A bare
`[[m]]` is a 27 ms blip. Consonants are therefore spoken with a following schwa
("the /m/ sound -- muh"), which is how phonemic charts present them anyway and
lands every consonant in a uniform 0.37-0.51 s.

Usage
-----
    python tool/generate_ipa_audio.py --check          # verify mapping only
    python tool/generate_ipa_audio.py                  # regenerate assets
    python tool/generate_ipa_audio.py --voice en-us    # American set

Requires espeak-ng (>= 1.5) and ffmpeg/numpy; see --espeak/--ffmpeg/--espeak-data.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave
from dataclasses import dataclass

import numpy as np

SR = 22050
SPEED = 110             # espeak words-per-minute; see module docstring
SILENCE_DB = -60.0      # mean volume below this counts as an empty clip

VOWELS = "vowel"
CONSONANT = "consonant"


@dataclass(frozen=True)
class Phone:
    mnemonic: str       # espeak's own phoneme symbol
    anchor: str         # English word in which espeak realises that phoneme
    kind: str

    @property
    def body(self) -> str:
        """Text fed to espeak inside [[...]].

        Consonants take a schwa tail so the release is audible: espeak renders a
        lone voiced consonant as a ~30 ms fragment.
        """
        return self.mnemonic if self.kind == VOWELS else self.mnemonic + "@"


PHONES: dict[str, Phone] = {
    # ---- monophthongs ----
    "i_long":      Phone("i:", "see",     VOWELS),
    "i_short":     Phone("I",  "sit",     VOWELS),
    "e":           Phone("E",  "bed",     VOWELS),   # English /e/ is [ɛ], not cardinal [e]
    "ae":          Phone("a",  "cat",     VOWELS),
    "er_long":     Phone("3:", "bird",    VOWELS),
    "schwa":       Phone("@",  "vision",  VOWELS),
    "v_short":     Phone("V",  "cup",     VOWELS),   # the sound that prompted this rewrite
    "u_long":      Phone("u:", "food",    VOWELS),
    "u_short":     Phone("U",  "book",    VOWELS),
    "o_long":      Phone("O:", "law",     VOWELS),
    "o_short":     Phone("0",  "hot",     VOWELS),
    "a_long":      Phone("A:", "father",  VOWELS),
    # ---- diphthongs ----
    "ei":          Phone("eI", "day",     VOWELS),
    "ai":          Phone("aI", "time",    VOWELS),
    "oi":          Phone("OI", "boy",     VOWELS),
    "ou":          Phone("oU", "go",      VOWELS),
    "au":          Phone("aU", "now",     VOWELS),
    "ie_schwa":    Phone("i@", "near",    VOWELS),
    "e_schwa":     Phone("e@", "hair",    VOWELS),
    "u_schwa":     Phone("U@", "tour",    VOWELS),
    # ---- plosives ----
    "p":           Phone("p",  "pen",     CONSONANT),
    "b":           Phone("b",  "bed",     CONSONANT),
    "t":           Phone("t",  "tea",     CONSONANT),
    "d":           Phone("d",  "dog",     CONSONANT),
    "k":           Phone("k",  "cat",     CONSONANT),
    "g":           Phone("g",  "go",      CONSONANT),
    # ---- fricatives ----
    "f":           Phone("f",  "fan",     CONSONANT),
    "v":           Phone("v",  "van",     CONSONANT),
    "th_unvoiced": Phone("T",  "thin",    CONSONANT),
    "th_voiced":   Phone("D",  "this",    CONSONANT),
    "s":           Phone("s",  "sun",     CONSONANT),
    "z":           Phone("z",  "zoo",     CONSONANT),
    "sh":          Phone("S",  "she",     CONSONANT),
    "zh":          Phone("Z",  "vision",  CONSONANT),
    "h":           Phone("h",  "hat",     CONSONANT),
    # ---- affricates ----
    "ch":          Phone("tS", "chair",   CONSONANT),
    "dzh":         Phone("dZ", "jump",    CONSONANT),
    # ---- nasals ----
    "m":           Phone("m",  "man",     CONSONANT),
    "n":           Phone("n",  "nose",    CONSONANT),
    "ng":          Phone("N",  "sing",    CONSONANT),
    # ---- approximants ----
    "l":           Phone("l",  "leg",     CONSONANT),
    "r":           Phone("r",  "red",     CONSONANT),
    "w":           Phone("w",  "wet",     CONSONANT),
    "j":           Phone("j",  "yes",     CONSONANT),
    # ---- clusters ----
    "tr":          Phone("tr", "tree",    CONSONANT),
    "dr":          Phone("dr", "dream",   CONSONANT),
    "ts":          Phone("ts", "cats",    CONSONANT),
    "dz":          Phone("dz", "beds",    CONSONANT),
}


def which(name: str, override: str | None) -> str:
    if override:
        return override
    found = shutil.which(name)
    if not found:
        sys.exit(f"error: {name} not found; pass an explicit path or put it on PATH")
    return found


def espeak_env(espeak: str, data_dir: str | None) -> dict[str, str]:
    """espeak-ng looks for `espeak-ng-data` beside its binary.

    Without ESPEAK_DATA_PATH it *crashes* on Windows (0xC0000005, access
    violation) and prints nothing at all, so a naive caller silently gets empty
    output and would happily write 48 silent clips. Always set it explicitly.
    """
    env = dict(os.environ)
    if data_dir:
        env["ESPEAK_DATA_PATH"] = data_dir
    elif "ESPEAK_DATA_PATH" not in env:
        beside = os.path.join(os.path.dirname(os.path.abspath(espeak)), "espeak-ng-data")
        if os.path.isdir(beside):
            env["ESPEAK_DATA_PATH"] = os.path.dirname(beside)
    return env


def espeak_out(espeak: str, args: list[str], env: dict[str, str]) -> str:
    p = subprocess.run([espeak, *args], capture_output=True, text=True, env=env)
    if p.returncode != 0:
        raise RuntimeError(
            f"espeak-ng failed (rc={p.returncode}; 0xC0000005 means a missing data "
            f"directory) for {' '.join(args)}: {p.stderr.strip()[:120]}"
        )
    return p.stdout.strip()


def verify(espeak: str, voice: str, env: dict[str, str]) -> list[str]:
    """Assert each mnemonic really is the phoneme espeak uses for its anchor."""
    failures = []
    for key, phone in PHONES.items():
        mnemonics = espeak_out(espeak, ["-v", voice, "-q", "-x", phone.anchor], env)
        ipa = espeak_out(espeak, ["-v", voice, "-q", "--ipa", phone.anchor], env)
        if phone.mnemonic not in mnemonics:
            failures.append(f"{key}: {phone.mnemonic!r} not in {phone.anchor!r} -> {mnemonics!r} ({ipa})")
    return failures


def synth(espeak: str, voice: str, phone: Phone, speed: int, out_wav: str, env: dict[str, str]) -> None:
    p = subprocess.run(
        [espeak, "-v", voice, "-s", str(speed), "-w", out_wav, f"[[{phone.body}]]"],
        capture_output=True, env=env,
    )
    if p.returncode != 0:
        raise RuntimeError(f"espeak-ng synthesis failed for [[{phone.body}]] (rc={p.returncode})")


def normalise(seg: np.ndarray, target_rms_db: float = -20.0, peak_db: float = -1.0) -> np.ndarray:
    """Match perceived level across phones without clipping.

    ffmpeg's loudnorm does not converge on 0.3-0.5 s clips and left a 12 dB
    spread between vowels and consonants, so levels are set here instead: scale
    to a common RMS, then back off if that would push the peak past the ceiling.
    """
    rms = float(np.sqrt(np.mean(seg ** 2)))
    peak = float(np.max(np.abs(seg)))
    if rms < 1e-9 or peak < 1e-9:
        return seg
    gain = (10 ** (target_rms_db / 20)) / rms
    gain = min(gain, (10 ** (peak_db / 20)) / peak)
    return seg * gain


def trim(src: str, dst: str, margin_ms: float = 5.0, floor_db: float = -70.0) -> float:
    """Drop espeak's 301 ms tail pad and any lead-in; return the active length.

    Threshold is relative to the clip's own peak, because a nasal or a /v/ peaks
    around -25 dBFS while a vowel peaks near 0, and an absolute gate would eat
    the quiet ones whole.
    """
    with wave.open(src) as w:
        sr, nchan = w.getframerate(), w.getnchannels()
        raw = w.readframes(w.getnframes())
    a = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if nchan > 1:
        a = a.reshape(-1, nchan).mean(axis=1)
    if not len(a):
        raise RuntimeError(f"espeak produced no samples for {src}")
    peak = float(np.max(np.abs(a)))
    if peak < 1e-6:
        raise RuntimeError(f"espeak produced digital silence for {src}")
    thr = max(peak * 0.02, 10 ** (floor_db / 20))
    idx = np.where(np.abs(a) > thr)[0]
    if not len(idx):
        raise RuntimeError(f"no active region found in {src}")
    margin = int(sr * margin_ms / 1000)
    seg = a[max(0, idx[0] - margin): min(len(a), idx[-1] + margin)].copy()
    seg = normalise(seg)
    fade = min(int(sr * 0.005), len(seg) // 4)
    if fade > 1:
        seg[:fade] *= np.linspace(0.0, 1.0, fade, dtype=np.float32)
        seg[-fade:] *= np.linspace(1.0, 0.0, fade, dtype=np.float32)
    with wave.open(dst, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(seg, -1.0, 1.0) * 32767).astype(np.int16).tobytes())
    return len(seg) / sr


def encode(ffmpeg: str, src_wav: str, dst_mp3: str) -> None:
    subprocess.run(
        [ffmpeg, "-y", "-i", src_wav, "-ac", "1", "-ar", str(SR),
         "-b:a", "64k", dst_mp3],
        check=True, capture_output=True,
    )


def mean_db(ffmpeg: str, path: str) -> float:
    r = subprocess.run([ffmpeg, "-i", path, "-af", "volumedetect", "-f", "null", "-"],
                       capture_output=True, text=True)
    m = re.search(r"mean_volume:\s*(-?[\d.]+) dB", r.stderr)
    return float(m.group(1)) if m else 0.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--espeak", default=os.environ.get("ESPEAK_NG"))
    ap.add_argument("--espeak-data", default=os.environ.get("ESPEAK_DATA_PATH"))
    ap.add_argument("--ffmpeg", default=os.environ.get("FFMPEG"))
    ap.add_argument("--voice", default="en-gb-x-rp",
                    help="espeak-ng voice: en-gb-x-rp (RP chart) or en-us (American)")
    ap.add_argument("--speed", type=int, default=SPEED, help="espeak words per minute")
    ap.add_argument("--out", default=os.path.join("assets", "audio", "ipa"))
    ap.add_argument("--check", action="store_true", help="verify the mapping and exit")
    args = ap.parse_args()

    espeak = which("espeak-ng", args.espeak)
    env = espeak_env(espeak, args.espeak_data)

    failures = verify(espeak, args.voice, env)
    print(f"repertoire check ({args.voice}): {len(PHONES) - len(failures)}/{len(PHONES)} mnemonics confirmed")
    for f in failures:
        print("  MISMATCH:", f)
    if args.check or failures:
        return 1 if failures else 0

    ffmpeg = which("ffmpeg", args.ffmpeg)
    os.makedirs(args.out, exist_ok=True)

    rows: list[tuple[str, float, float, int]] = []
    problems: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        for key, phone in sorted(PHONES.items()):
            raw = os.path.join(tmp, f"{key}.wav")
            cut = os.path.join(tmp, f"{key}.trim.wav")
            mp3 = os.path.join(args.out, f"{key}.mp3")
            synth(espeak, args.voice, phone, args.speed, raw, env)
            active = trim(raw, cut)
            encode(ffmpeg, cut, mp3)
            db = mean_db(ffmpeg, mp3)
            rows.append((key, active, db, os.path.getsize(mp3)))
            if db < SILENCE_DB:
                problems.append(f"{key} is silent ({db:.1f} dB)")
            elif active < 0.12:
                problems.append(f"{key} is only {active:.3f}s")

    print(f"\n{'key':<14}{'sec':>7}{'mean dB':>10}{'bytes':>8}")
    for key, dur, db, size in rows:
        print(f"{key:<14}{dur:>7.3f}{db:>10.1f}{size:>8}")
    print(f"\nwrote {len(rows)} files to {args.out}")
    if problems:
        print("PROBLEMS:")
        for p in problems:
            print("  -", p)
        return 1
    shortest = min(rows, key=lambda r: r[1])
    print(f"all clips audible; shortest is {shortest[0]} at {shortest[1]:.3f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
