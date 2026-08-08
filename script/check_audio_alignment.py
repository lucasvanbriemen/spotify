#!/usr/bin/env python3
"""Estimates the time offset (in seconds) between two recordings of the same
song, so VocalSeparation can tell whether a YouTube karaoke upload actually
starts at the same instant as the original — a different upload can have
the right overall duration (already checked before this runs) while still
adding a few seconds of lead-in, which would silently desync both lyrics
and scoring for the rest of the song.

Cross-correlates onset-strength envelopes (a structural/rhythmic signature)
rather than raw audio, since the two recordings differ in mastering/EQ but
should share the same musical events if they're really time-aligned.

Usage: python check_audio_alignment.py <reference_audio> <candidate_audio>
Prints the offset in seconds (candidate relative to reference) to stdout.
"""
import argparse

import librosa
import numpy as np

SAMPLE_RATE = 22050
HOP_LENGTH = 512
# Comparing more than this wastes time without improving the estimate — the
# offset (if any) is already obvious from the first minute.
MAX_COMPARE_SECONDS = 60


def onset_envelope(path):
    y, _ = librosa.load(path, sr=SAMPLE_RATE, mono=True, duration=MAX_COMPARE_SECONDS)
    return librosa.onset.onset_strength(y=y, sr=SAMPLE_RATE, hop_length=HOP_LENGTH)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference_audio")
    parser.add_argument("candidate_audio")
    args = parser.parse_args()

    reference = onset_envelope(args.reference_audio)
    candidate = onset_envelope(args.candidate_audio)

    limit = min(len(reference), len(candidate))
    reference, candidate = reference[:limit], candidate[:limit]

    correlation = np.correlate(candidate - candidate.mean(), reference - reference.mean(), mode="full")
    lag_frames = correlation.argmax() - (limit - 1)
    print(round(float(lag_frames * HOP_LENGTH / SAMPLE_RATE), 3))


if __name__ == "__main__":
    main()
