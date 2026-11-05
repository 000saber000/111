#!/usr/bin/env python3
"""Deterministic SFX generator for the Godot farming game.

Writes three mono 16-bit PCM WAVs at 22050 Hz into assets/audio/:

    plant.wav    ~140 ms  damped low thud (110 -> 55 Hz) + short soil puff
    harvest.wav  ~280 ms  soft pop + ascending C5-E5-G5 pluck arpeggio
    coin.wav     ~200 ms  bright detuned double bell + tiny shimmer

The script then re-reads every file with the *stdlib* ``wave`` module,
prints a measurement table and a 40-bucket ASCII peak envelope, and
asserts the format/energy/shape contract.  Re-running it produces
byte-identical WAVs (no RNG state leaks, no external audio).

Python 3.10+, standard library only (math, struct, wave, pathlib, sys).
Run from anywhere:  python tools/audio/generate_sfx.py
"""

from __future__ import annotations

import math
import struct
import sys
import wave
from pathlib import Path

# ---------------------------------------------------------------- constants

SR = 22050                 # sample rate, Hz
CHANNELS = 1               # mono
SAMPWIDTH = 2              # 16-bit signed PCM
FADE_S = 0.005             # 5 ms linear fade in and out
FADE_N = int(round(FADE_S * SR))  # 110 samples
PEAK = 0.707               # ~ -3 dBFS full-scale target
SIZE_LIMIT = 60 * 1024     # each file must stay below 60 KB
RMS_FLOOR_DB = -28.0       # audible energy floor

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "audio"

# name -> exact duration in seconds
DURATIONS = {"plant": 0.140, "harvest": 0.280, "coin": 0.200}

TAU = 2.0 * math.pi


# ------------------------------------------------------------------ helpers

class LCG:
    """Deterministic white-noise source, independent of the ``random`` module."""

    __slots__ = ("state",)

    def __init__(self, seed: int) -> None:
        self.state = (seed & 0x7FFFFFFF) or 0x1234567

    def uniform(self) -> float:
        """Return a value in [-1.0, 1.0)."""
        self.state = (1103515245 * self.state + 12345) & 0x7FFFFFFF
        return self.state / 1073741823.5 - 1.0


def unit_peak(samples: list[float]) -> list[float]:
    """Scale a signal so its absolute peak is exactly 1.0 (silent -> zeros)."""
    peak = max((abs(v) for v in samples), default=0.0)
    if peak <= 1e-12:
        return [0.0] * len(samples)
    return [v / peak for v in samples]


def lowpass(samples: list[float], cutoff_hz: float, order: int = 1) -> list[float]:
    """One-pole low-pass, applied ``order`` times for a steeper slope."""
    a = 1.0 - math.exp(-TAU * cutoff_hz / SR)
    out = list(samples)
    for _ in range(order):
        z = 0.0
        filtered: list[float] = []
        for v in out:
            z += a * (v - z)
            filtered.append(z)
        out = filtered
    return out


def fade_shape(n: int) -> list[float]:
    """Linear 5 ms fade-in and fade-out weights (zero at both endpoints)."""
    w = [1.0] * n
    for i in range(FADE_N):
        g = i / (FADE_N - 1)
        w[i] = g
        w[n - 1 - i] = g
    return w


def finish(signal: list[float]) -> list[float]:
    """Remove DC, apply 5 ms linear fades, then normalise peak to PEAK.

    A plain ``x - mean(x)`` before fading still leaves residual DC: fading a
    55 Hz thud over 5 ms re-weights its first/last partial cycles.  So the
    DC correction is subtracted with the *same* fade shape (zero at the
    endpoints, ~1 in the middle), which drives the mean to 0 without putting
    a step discontinuity at sample 0 or n-1.
    """
    n = len(signal)
    ramp = fade_shape(n)
    mean = sum(signal) / n
    x = [(v - mean) * w for v, w in zip(signal, ramp)]

    residual = sum(x) / n
    weight_mean = sum(ramp) / n
    offset = residual / weight_mean
    x = [v - offset * w for v, w in zip(x, ramp)]

    peak = max(abs(v) for v in x)
    scale = PEAK / peak
    return [v * scale for v in x]


def quantize(signal: list[float]) -> list[int]:
    """Float [-1, 1) -> int16, rounded, hard-clipped for safety."""
    out = []
    for v in signal:
        q = int(round(v * 32767.0))
        if q > 32767:
            q = 32767
        elif q < -32768:
            q = -32768
        out.append(q)
    return out


# ---------------------------------------------------------------- synthesis

def synth_plant() -> list[float]:
    """Dampened low thud: gliding 110 -> 55 Hz body + very short soil puff.

    Body   : sine plus low-order harmonics (0.20, 0.14, 0.08, 0.04) so the
             thud still reads on a phone speaker, 1.5 ms attack, tau 40 ms.
             Instantaneous pitch 55 + 55*exp(-t/55 ms): 110 Hz -> ~59 Hz.
    Puff   : white noise, two-pole low-pass at 1100 Hz, 0.8 ms attack,
             tau 8.5 ms, gain 0.70.  Reads as soil, not as a click.
    """
    n = int(round(DURATIONS["plant"] * SR))
    rng = LCG(0x5EED_0001)
    noise = lowpass([rng.uniform() for _ in range(n)], 1100.0, order=2)
    puff = unit_peak(noise)

    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        freq = 55.0 + 55.0 * math.exp(-t / 0.055)
        phase += TAU * freq / SR

        body = (
            math.sin(phase)
            + 0.20 * math.sin(2.0 * phase)
            + 0.14 * math.sin(3.0 * phase)
            + 0.08 * math.sin(4.0 * phase)
            + 0.04 * math.sin(5.0 * phase)
        )
        body_env = (1.0 - math.exp(-t / 0.0015)) * math.exp(-t / 0.040)

        puff_env = (1.0 - math.exp(-t / 0.0008)) * math.exp(-t / 0.0085)
        out.append(0.90 * body_env * body + 0.70 * puff_env * puff[i])
    return out


def synth_harvest() -> list[float]:
    """Soft pop, then a quick C5-E5-G5 pluck arpeggio.

    Pop    : 3 kHz low-passed noise burst, tau 4.5 ms, gain 0.30
             + short sine blip 600 -> 320 Hz, tau 14 ms, gain 0.28.
    Notes  : start 30 / 90 / 150 ms, 2.5 ms attack.
             fundamental (tau 55 ms) + 0.28*h2 (tau 30 ms)
             + 0.10*h3 (tau 18 ms), per-note gain 0.85 / 0.95 / 1.00.
    """
    n = int(round(DURATIONS["harvest"] * SR))
    rng = LCG(0x5EED_0002)
    noise = unit_peak(lowpass([rng.uniform() for _ in range(n)], 3000.0, order=1))

    out = [0.0] * n

    # -- soft pop transient
    blip_phase = 0.0
    for i in range(n):
        t = i / SR
        click_env = (1.0 - math.exp(-t / 0.0005)) * math.exp(-t / 0.0045)
        out[i] += 0.30 * click_env * noise[i]

        blip_freq = 320.0 + 280.0 * math.exp(-t / 0.008)
        blip_phase += TAU * blip_freq / SR
        blip_env = (1.0 - math.exp(-t / 0.0010)) * math.exp(-t / 0.014)
        out[i] += 0.28 * blip_env * math.sin(blip_phase)

    # -- ascending pluck arpeggio
    notes = ((523.25, 0.030, 0.85),   # C5
             (659.25, 0.090, 0.95),   # E5
             (783.99, 0.150, 1.00))   # G5
    for freq, start_s, gain in notes:
        start = int(round(start_s * SR))
        for i in range(start, n):
            t = (i - start) / SR
            attack = 1.0 - math.exp(-t / 0.0025)
            voice = (
                math.sin(TAU * freq * t) * math.exp(-t / 0.055)
                + 0.28 * math.sin(TAU * 2.0 * freq * t) * math.exp(-t / 0.030)
                + 0.10 * math.sin(TAU * 3.0 * freq * t) * math.exp(-t / 0.018)
            )
            out[i] += gain * attack * voice
    return out


def synth_coin() -> list[float]:
    """Bright but not shrill coin: detuned double bell with fast decay.

    Partials (each a pair of sines f and f+detune, averaged to keep gain):
        1568 Hz +/-7 Hz  gain 0.50  tau 52 ms
        2093 Hz +/-9 Hz  gain 0.70  tau 46 ms
        3136 Hz +/-7 Hz  gain 0.14  tau 26 ms  (shimmer)
        4186 Hz +/-9 Hz  gain 0.05  tau 16 ms
        6272 Hz +/-13 Hz gain 0.02  tau 10 ms  (air, just a hint)
    The detuned twin decays 15 % faster than its partner: the pair still
    beats (metallic shimmer) but never cancels back into an audible "wah".
    Global 1.2 ms attack; beat rates 7 / 9 / 14 / 18 / 26 Hz.
    """
    n = int(round(DURATIONS["coin"] * SR))
    partials = (
        (1568.0, 7.0, 0.50, 0.052),
        (2093.0, 9.0, 0.70, 0.046),
        (3136.0, 7.0, 0.14, 0.026),
        (4186.0, 9.0, 0.05, 0.016),
        (6272.0, 13.0, 0.02, 0.010),
    )
    twin_decay = 0.85

    out: list[float] = []
    for i in range(n):
        t = i / SR
        attack = 1.0 - math.exp(-t / 0.0012)
        s = 0.0
        for freq, detune, gain, tau in partials:
            pair = 0.5 * (
                math.sin(TAU * freq * t) * math.exp(-t / tau)
                + math.sin(TAU * (freq + detune) * t)
                * math.exp(-t / (tau * twin_decay))
            )
            s += gain * pair
        out.append(attack * s)
    return out


SYNTH = {
    "plant": synth_plant,
    "harvest": synth_harvest,
    "coin": synth_coin,
}


# ------------------------------------------------------------------- output

def write_wav(path: Path, samples: list[int]) -> None:
    data = struct.pack("<%dh" % len(samples), *samples)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(CHANNELS)
        w.setsampwidth(SAMPWIDTH)
        w.setframerate(SR)
        w.writeframes(data)


# --------------------------------------------------------------- verification

def dbfs(amplitude: float) -> float:
    if amplitude <= 0.0:
        return -math.inf
    return 20.0 * math.log10(amplitude)


def envelope_buckets(samples: list[int], buckets: int = 40) -> list[float]:
    n = len(samples)
    values = []
    for b in range(buckets):
        lo = b * n // buckets
        hi = max(lo + 1, (b + 1) * n // buckets)
        values.append(max(abs(v) for v in samples[lo:hi]) / 32768.0)
    return values


LEVEL_CHARS = " .:-=+*#%@"


def print_envelope(env: list[float], label: str) -> None:
    peak = max(env) or 1.0
    bar = "".join(
        LEVEL_CHARS[min(len(LEVEL_CHARS) - 1, int(round((v / peak) * (len(LEVEL_CHARS) - 1))))]
        for v in env
    )
    print(f"  {label:<9} 40 buckets, peak bucket={peak:.3f} FS")
    print(f"  |{bar}|")
    print("  |" + "".join(str((i // 10) % 10) for i in range(len(env))) + "|  (bucket tens)")


def smooth_envelope(env: list[float], radius: int = 2) -> list[float]:
    """Moving average that removes the peak-envelope ripple of a low tone."""
    out = []
    for i in range(len(env)):
        lo = max(0, i - radius)
        hi = min(len(env), i + radius + 1)
        out.append(sum(env[lo:hi]) / (hi - lo))
    return out


def count_bumps(env: list[float], rel: float = 0.30, gap: int = 3) -> list[int]:
    """Indices of clear local maxima in the bucket envelope."""
    peak = max(env)
    peaks: list[int] = []
    for i in range(1, len(env) - 1):
        if env[i] >= env[i - 1] and env[i] > env[i + 1] and env[i] >= rel * peak:
            if peaks and i - peaks[-1] < gap:
                if env[i] > env[peaks[-1]]:
                    peaks[-1] = i
            else:
                peaks.append(i)
    return peaks


def analyze(name: str, failures: list[str]) -> None:
    path = OUT_DIR / f"{name}.wav"
    target_s = DURATIONS[name]

    with wave.open(str(path), "rb") as w:
        channels = w.getnchannels()
        sampwidth = w.getsampwidth()
        framerate = w.getframerate()
        frames = w.getnframes()
        raw = w.readframes(frames)

    samples = list(struct.unpack("<%dh" % frames, raw))
    n = len(samples)
    peak_raw = max(abs(v) for v in samples)
    peak_fs = peak_raw / 32768.0
    peak_db = dbfs(peak_fs)
    rms_raw = math.sqrt(sum(v * v for v in samples) / n)
    rms_fs = rms_raw / 32768.0
    rms_db = dbfs(rms_fs)
    dc = sum(samples) / n / 32768.0
    duration_ms = frames / framerate * 1000.0
    size = path.stat().st_size

    print(f"\n=== {path.relative_to(ROOT)} ===")
    print(f"  channels={channels}  sample_width={sampwidth * 8}-bit  "
          f"frame_rate={framerate}  frames={frames}")
    print(f"  duration={duration_ms:7.2f} ms (target {target_s * 1000:.1f} ms)   "
          f"file_size={size} B")
    print(f"  peak={peak_db:+.2f} dBFS ({peak_fs:.4f} FS)   "
          f"RMS={rms_db:+.2f} dBFS ({rms_fs:.4f} FS)")
    print(f"  DC={dc:+.6f}   first={samples[0]}   last={samples[-1]}")
    raw_env = envelope_buckets(samples)
    shape_env = smooth_envelope(raw_env, radius=2)
    print_envelope(raw_env, "peak")
    print_envelope(shape_env, "smoothed")
    bumps = count_bumps(shape_env, rel=0.30, gap=3)
    print(f"  smoothed envelope bumps at buckets {bumps}")
    peak_bucket = shape_env.index(max(shape_env))

    def check(cond: bool, msg: str) -> None:
        if not cond:
            failures.append(f"{name}: {msg}")

    check(channels == 1, f"channels {channels} != 1")
    check(sampwidth == 2, f"sample width {sampwidth} != 2")
    check(framerate == SR, f"frame rate {framerate} != {SR}")
    check(abs(frames - round(target_s * SR)) <= 1,
          f"frame count {frames} != {round(target_s * SR)}")
    check(abs(duration_ms - target_s * 1000.0) < 2.0,
          f"duration {duration_ms:.2f} ms off target {target_s * 1000:.1f} ms")
    check(peak_raw < 32767, "signal clips at int16 full scale")
    check(-3.5 <= peak_db <= -2.5, f"peak {peak_db:+.2f} dBFS not near -3 dBFS")
    check(rms_db >= RMS_FLOOR_DB, f"RMS {rms_db:+.2f} dBFS below {RMS_FLOOR_DB} dBFS")
    check(abs(dc) <= 0.001, f"DC offset {dc:+.6f} too large")
    check(size < SIZE_LIMIT, f"file size {size} B >= {SIZE_LIMIT} B")
    check(samples[0] == 0, f"first sample {samples[0]} != 0 (click risk)")
    check(samples[-1] == 0, f"last sample {samples[-1]} != 0 (click risk)")

    if name == "plant":
        check(peak_bucket <= 3, "thud attack is not at the start")
        check(shape_env[-1] <= 0.15 * max(shape_env), "thud does not decay to silence")
        rebound = next((i for i in range(peak_bucket + 3, len(shape_env))
                        if shape_env[i] > shape_env[i - 1] * 1.05 + 0.003), None)
        check(rebound is None, f"thud envelope rebounds at bucket {rebound}")
        check(len(bumps) <= 1, f"thud has {len(bumps)} bumps, expected 1")
    elif name == "harvest":
        check(len(bumps) >= 3, f"arpeggio shows {len(bumps)} bumps, expected >= 3")
        check(peak_bucket <= 27, "arpeggio peak is too late")
    elif name == "coin":
        check(peak_bucket <= 4, "bell attack is not at the start")
        # Fast fall: by 25 % of the file the bell is already well down.
        check(shape_env[len(shape_env) // 4] <= 0.25 * max(shape_env),
              "bell decays too slowly")
        # What remains is only the quiet detune shimmer, never a new hit.
        check(max(shape_env[len(shape_env) // 3:]) <= 0.15 * max(shape_env),
              "bell tail rings too loudly")
        check(shape_env[-1] <= 0.05 * max(shape_env), "bell does not decay to silence")


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"writing to {OUT_DIR}")
    for name, synth in SYNTH.items():
        signal = synth()
        samples = quantize(finish(signal))
        path = OUT_DIR / f"{name}.wav"
        write_wav(path, samples)
        print(f"  wrote {path.name}: {len(samples)} frames, "
              f"{path.stat().st_size} B")

    failures: list[str] = []
    for name in DURATIONS:
        analyze(name, failures)

    print("\n" + "=" * 64)
    if failures:
        print("FAILED:")
        for msg in failures:
            print("  - " + msg)
        return 1
    print("ALL CHECKS PASSED: 22050 Hz / 16-bit / mono, peak ~-3 dBFS, "
          "RMS > -28 dBFS, no DC, no clicks, sizes < 60 KB, shapes OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
