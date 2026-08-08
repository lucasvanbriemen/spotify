#!/usr/bin/env python3
"""Separates a song into a vocal-free instrumental and a reference pitch
curve for the karaoke feature's live scoring.

The isolated vocal stem demucs produces is read only long enough to extract
its pitch curve — it is never written outside a temp directory, and that
directory is discarded before this script exits. Only the instrumental
audio and the extracted pitch numbers survive.

Usage:
    python karaoke_separate.py <input_audio> <instrumental_wav_out> <pitch_json_out> [--model htdemucs]
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import librosa
import numpy as np

# 25ms frames: fine enough to track a sung melody (including vibrato) without
# an unreasonably large pitch-curve JSON for a multi-minute song.
HOP_SECONDS = 0.025
FMIN_NOTE = "C2"
FMAX_NOTE = "C6"


def separate(input_path, model, work_dir):
    subprocess.run(
        [sys.executable, "-m", "demucs", "--two-stems", "vocals", "-n", model, "-o", str(work_dir), str(input_path)],
        check=True, capture_output=True, text=True,
    )

    stem_dir = work_dir / model / Path(input_path).stem
    return stem_dir / "vocals.wav", stem_dir / "no_vocals.wav"


# A reference melody as (time, frequency) pairs, one per hop; frequency is
# None for instrumental gaps / unvoiced frames the singer has nothing to
# match. Downstream (the browser) compares its own live pitch estimate
# against the point nearest the current playback time.
def extract_pitch(vocals_path):
    y, sr = librosa.load(vocals_path, sr=None, mono=True)
    hop_length = max(1, round(sr * HOP_SECONDS))

    f0, voiced_flag, _voiced_prob = librosa.pyin(
        y, fmin=librosa.note_to_hz(FMIN_NOTE), fmax=librosa.note_to_hz(FMAX_NOTE), sr=sr, hop_length=hop_length
    )

    hz = [
        round(float(value), 2) if voiced and not np.isnan(value) else None
        for value, voiced in zip(f0, voiced_flag)
    ]
    return hop_length / sr, hz


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_audio")
    parser.add_argument("instrumental_out")
    parser.add_argument("pitch_out")
    parser.add_argument("--model", default="htdemucs", help="demucs model name")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="karaoke-separate-") as tmp:
        work_dir = Path(tmp)
        vocals_path, instrumental_path = separate(args.input_audio, args.model, work_dir)

        hop_seconds, hz = extract_pitch(vocals_path)
        Path(args.pitch_out).write_text(json.dumps({"hop_seconds": hop_seconds, "hz": hz}))

        shutil.move(str(instrumental_path), args.instrumental_out)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stdout or "")
        sys.stderr.write(error.stderr or "")
        sys.exit(1)
