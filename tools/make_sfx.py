#!/usr/bin/env python3
"""Build the game's SFX WAVs (16-bit mono) into audio/.

    python3 -I tools/make_sfx.py
        -> game_over.wav  (synthesized Duolingo-style lose jingle)

    python3 -I tools/make_sfx.py --trim <recording.wav> [more.wav ...]
        -> chop_1..N.wav  one variant per recording, silence cut from both
           ends. Sources: user-provided Firefly renders, converted first via
           ffmpeg -i in.wav -ac 1 -ar 44100 -sample_fmt s16 out.wav
           (see audio/SOURCES.md)

Only game_over.wav needs regeneration when the jingle changes; the chops
are rebuilt only from their source recordings.
"""
import math
import os
import struct
import sys
import wave

SR = 44100
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio"))


def read_wav(path):
    with wave.open(path) as w:
        assert w.getnchannels() == 1 and w.getframerate() == SR and w.getsampwidth() == 2, \
            "feed 16-bit mono 44.1 kHz: ffmpeg -i in -ac 1 -ar 44100 -sample_fmt s16 out.wav"
        return list(struct.unpack("<%dh" % w.getnframes(), w.readframes(w.getnframes())))


def write_wav(name, samples, peak=0.9):
    m = max(1e-9, max(abs(s) for s in samples))
    scale = peak / m
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767.0))
        for s in samples
    )
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    print("%-16s %.2fs" % (name, len(samples) / SR))


def fade_tail(samples, seconds=0.015):
    n = int(SR * seconds)
    for i in range(min(n, len(samples))):
        samples[-1 - i] *= i / n
    return samples


# ------------------------------------------------------------------ chop ---

def trim_silence(x, head_pad_ms=4, tail_floor=0.04, tail_pad_ms=20, fade_ms=15):
    """Cut silence from both ends (5 ms envelope, floors as fraction of peak)."""
    win = SR // 200
    e = [sum(abs(v) for v in x[i:i + win]) / len(x[i:i + win]) for i in range(0, len(x), win)]
    pk = max(e)
    on = next(i for i, v in enumerate(e) if v > 0.05 * pk)
    off = len(e) - 1 - next(i for i, v in enumerate(reversed(e)) if v > tail_floor * pk)
    head = max(0, on * win - head_pad_ms * SR // 1000)
    tail = min(len(x), (off + 1) * win + tail_pad_ms * SR // 1000)
    x = x[head:tail]
    n = int(SR * fade_ms / 1000)
    for i in range(min(n, len(x))):
        x[-1 - i] *= i / n
    return x


def build_chops(paths):
    """One chop variant per recording: DC removed, silence cut, normalized."""
    for i, path in enumerate(paths):
        x = read_wav(path)
        x = [s - sum(x) / len(x) for s in x]
        write_wav("chop_%d.wav" % (i + 1), trim_silence(x))


# ------------------------------------------------------------- game over ---

def chip_note(out, start, f, dur, amp, duty=0.25):
    """Game-music voice: softened square (the sub carries the body)."""
    s0 = int(SR * start)
    period = SR / float(f)
    for i in range(int(SR * dur)):
        ph = (i % period) / period
        env = min(i / (SR * 0.004), 1.0) * math.exp(-2.6 * i / SR)
        if s0 + i < len(out):
            out[s0 + i] += amp * 0.6 * (1.0 if ph < duty else -1.0) * env
            out[s0 + i] += amp * 0.45 * (1.0 if (i % (2 * period)) < period else -1.0) * env


def build_game_over():
    # Original death tune in the game-jingle spirit (no existing melody
    # copied): a hopeful hop up, a comic chromatic slide, a low "da-dum".
    n = {"C5": 523.25, "E5": 659.26, "G5": 783.99, "B4": 493.88, "Bb4": 466.16,
         "A4": 440.00, "Ab4": 415.30, "G4": 392.00, "G3": 196.00, "C3": 130.81}
    phrase = [
        (0.00, "C5", 0.085), (0.10, "E5", 0.085), (0.20, "G5", 0.12),
        (0.33, "E5", 0.09), (0.45, "B4", 0.10), (0.56, "Bb4", 0.10),
        (0.67, "A4", 0.10), (0.78, "Ab4", 0.10), (0.89, "G4", 0.15),
        (1.06, "G3", 0.14), (1.20, "C3", 0.40),
    ]
    out = [0.0] * int(SR * 1.7)
    for start, note, dur in phrase:
        chip_note(out, start, n[note], dur, 0.32)
    fade_tail(out, 0.06)
    write_wav("game_over.wav", trim_silence(out, tail_floor=0.01), peak=0.8)


def main():
    os.makedirs(OUT, exist_ok=True)
    if "--trim" in sys.argv:
        rest = sys.argv[sys.argv.index("--trim") + 1:]
        assert rest, "usage: make_sfx.py --trim <recording.wav> [more.wav ...]"
        build_chops(rest)
    else:
        build_game_over()


if __name__ == "__main__":
    main()
