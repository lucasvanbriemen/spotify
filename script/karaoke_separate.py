#!/usr/bin/env python3
"""Produces the karaoke artifacts for one song: a vocal-free instrumental, the
isolated vocal stem, a reference pitch curve, a quantized note list and (when
synced lyrics are supplied) per-word timings.

The isolated vocal stem is a first-class output — it is written to
``--vocals-out`` because the karaoke stage plays it back, quietly, as the
vocal-guide fader. This deliberately reverses the earlier behaviour, where the
stem was read for its pitch curve and then discarded with the temp directory.

Lyrics are never fetched here: Ruby passes the LRC text in via ``--lrc`` (it
already has LRCLIB responses cached). Note and word analysis are pure functions
of the pitch curve, so ``--reanalyze`` can regenerate them from an existing
pitch.json in about a second, without re-running demucs.

Usage:
    python karaoke_separate.py <input_audio> <instrumental_wav_out> <pitch_json_out>
        [--model htdemucs] [--vocals-out out.wav] [--notes-out notes.json]
        [--words-out words.json] [--lrc lyrics.lrc]

    python karaoke_separate.py --reanalyze pitch.json --notes-out notes.json
        [--words-out words.json --lrc lyrics.lrc]

    python karaoke_separate.py --self-test
"""
import argparse
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

# 25ms frames: fine enough to track a sung melody (including vibrato) without
# an unreasonably large pitch-curve JSON for a multi-minute song.
HOP_SECONDS = 0.025
FMIN_NOTE = "C2"
FMAX_NOTE = "C6"
# pyin has no amplitude floor: it reports a confident pitch for the near-silent
# residue demucs leaves behind during instrumental sections, which becomes
# phantom notes in an intro nobody sings over. Measured on a real track, the
# intro of a separated stem sits ~590x quieter than the verse, so gating on a
# fraction of the track's own loud level cleanly separates the two.
SILENCE_RATIO = 0.02

# --- Note quantization tunables ------------------------------------------
# 125ms of median filtering flattens pyin's isolated octave blips while leaving
# vibrato (a few Hz) intact.
MEDIAN_FILTER_FRAMES = 5
# How far a frame may drift from its segment's running median before it counts
# as a new note rather than expressive movement within the current one.
NOTE_SPLIT_SEMITONES = 0.6
# Shorter than this is consonant flicker, not a note worth showing or scoring.
MIN_NOTE_SECONDS = 0.08
# pyin drops frames on consonants mid-note; bridge same-pitch segments across
# gaps this short so one sung note stays one note.
MERGE_GAP_SECONDS = 0.12
# Golden (bonus) notes: the top decile, but only ones that are a real hold.
GOLDEN_FRACTION = 0.10
GOLDEN_MIN_SECONDS = 0.30
# pyin occasionally locks onto a subharmonic or picks up low rumble bleeding
# through the stem, producing a handful of notes an octave or two below the
# melody. Left in, they wreck the pitch lane (which maps the whole range onto
# its height) and score as guaranteed misses on notes nobody sang. Dropped with
# the standard Tukey fence, so the cut adapts to how wide the song actually is
# instead of assuming a range.
OUTLIER_IQR_MULTIPLIER = 1.5
# Below this there aren't enough notes for quartiles to mean anything.
MIN_NOTES_FOR_OUTLIER_REJECTION = 12
# Voiced blips shorter than this are ignored when deciding where a line's words
# actually land in time.
MIN_VOICED_RUN_SECONDS = 0.05

TIMESTAMP_PATTERN = re.compile(r"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]")
# Enhanced LRC ("A2") word timings, e.g. "[00:12.30] <00:12.30> Hello <00:12.80> from".
WORD_TAG_PATTERN = re.compile(r"<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>")


# --- Separation & pitch extraction ---------------------------------------

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
    import librosa  # imported lazily: --reanalyze and --self-test don't need it

    y, sr = librosa.load(vocals_path, sr=None, mono=True)
    hop_length = max(1, round(sr * HOP_SECONDS))

    f0, voiced_flag, _voiced_prob = librosa.pyin(
        y, fmin=librosa.note_to_hz(FMIN_NOTE), fmax=librosa.note_to_hz(FMAX_NOTE), sr=sr, hop_length=hop_length
    )

    # Anything this quiet is separation residue, not the singer.
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=hop_length)[0]
    gate = float(np.percentile(rms, 99)) * SILENCE_RATIO
    loud = np.resize(rms > gate, len(f0))

    hz = [
        round(float(value), 2) if voiced and audible and not np.isnan(value) else None
        for value, voiced, audible in zip(f0, voiced_flag, loud)
    ]
    return hop_length / sr, hz


# --- Shared helpers -------------------------------------------------------

def _index_runs(mask):
    """Contiguous True stretches of mask, as (start, end-exclusive) indices."""
    runs = []
    start = None
    for index, value in enumerate(mask):
        if value and start is None:
            start = index
        elif not value and start is not None:
            runs.append((start, index))
            start = None
    if start is not None:
        runs.append((start, len(mask)))
    return runs


def hz_to_midi_array(hz):
    """The pitch curve as MIDI numbers, NaN where the frame is unvoiced."""
    values = np.array([np.nan if value is None else float(value) for value in hz], dtype=float)
    with np.errstate(divide="ignore", invalid="ignore"):
        midi = 69.0 + 12.0 * np.log2(values / 440.0)
    midi[~np.isfinite(midi)] = np.nan
    return midi


def _timestamp_seconds(match):
    minutes, seconds, fraction = match.group(1), match.group(2), match.group(3)
    total = int(minutes) * 60 + int(seconds)
    if fraction:
        total += int(fraction) / (10 ** len(fraction))
    return total


# --- notes.json -----------------------------------------------------------

def median_filter_runs(midi, width):
    """Median-filter each voiced run independently, so the filter never smears
    a note across the silence that separates it from the next one."""
    out = midi.copy()
    half = width // 2

    for start, end in _index_runs(np.isfinite(midi)):
        segment = midi[start:end]
        if segment.size < 3:
            continue

        filtered = np.empty_like(segment)
        for index in range(segment.size):
            low = max(0, index - half)
            high = min(segment.size, index + half + 1)
            filtered[index] = np.median(segment[low:high])
        out[start:end] = filtered

    return out


def reject_pitch_outliers(notes):
    """Drops notes lying outside the Tukey fence of the melody's own pitch
    distribution — the octave errors and rumble pyin leaves behind."""
    if len(notes) < MIN_NOTES_FOR_OUTLIER_REJECTION:
        return notes

    pitches = np.array([note["midi"] for note in notes], dtype=float)
    q1, q3 = np.percentile(pitches, [25, 75])
    spread = (q3 - q1) * OUTLIER_IQR_MULTIPLIER
    low, high = q1 - spread, q3 + spread

    kept = [note for note in notes if low <= note["midi"] <= high]
    # Never hand back an empty melody because the distribution was degenerate
    # (every note on one pitch makes the fence zero-width).
    return kept if kept else notes


def quantize_notes(hop_seconds, hz):
    """The sung melody as discrete notes: {notes: [{start, end, midi, golden}],
    midi_min, midi_max}. Empty notes are a legal result (rap, spoken word, a
    stem pyin can't track) — the client hides the pitch lane."""
    midi = median_filter_runs(hz_to_midi_array(hz), MEDIAN_FILTER_FRAMES)

    # Split each voiced run wherever the pitch departs from the note so far.
    # Comparing against the running median rather than the previous frame lets
    # vibrato stay inside one note.
    segments = []
    for run_start, run_end in _index_runs(np.isfinite(midi)):
        segment_start = run_start
        values = []

        for index in range(run_start, run_end):
            value = float(midi[index])
            if values and abs(value - float(np.median(values))) > NOTE_SPLIT_SEMITONES:
                segments.append((segment_start, index, float(np.median(values))))
                segment_start = index
                values = [value]
            else:
                values.append(value)

        if values:
            segments.append((segment_start, run_end, float(np.median(values))))

    # Merge before dropping, so two fragments of one note can combine into a
    # note long enough to survive MIN_NOTE_SECONDS.
    merged = []
    for start, end, value in segments:
        pitch = int(round(value))
        if merged and merged[-1]["midi"] == pitch and (start - merged[-1]["end"]) * hop_seconds < MERGE_GAP_SECONDS:
            merged[-1]["end"] = end
            continue
        merged.append({"start": start, "end": end, "midi": pitch})

    notes = [note for note in merged if (note["end"] - note["start"]) * hop_seconds >= MIN_NOTE_SECONDS]
    notes = reject_pitch_outliers(notes)
    if not notes:
        return {"notes": [], "midi_min": None, "midi_max": None}

    midi_min = min(note["midi"] for note in notes)
    midi_max = max(note["midi"] for note in notes)
    span = max(1, midi_max - midi_min)

    # Weighting duration by pitch height (1x at the song's lowest note, 2x at
    # its highest) biases golden notes towards held chorus climaxes. Ranking on
    # duration alone rewards low drones and backing-hum leakage instead.
    def bonus_weight(note):
        seconds = (note["end"] - note["start"]) * hop_seconds
        return seconds * (1 + (note["midi"] - midi_min) / span)

    ranked = sorted(range(len(notes)), key=lambda index: -bonus_weight(notes[index]))
    golden = {
        index for index in ranked[:math.ceil(GOLDEN_FRACTION * len(notes))]
        if (notes[index]["end"] - notes[index]["start"]) * hop_seconds >= GOLDEN_MIN_SECONDS
    }

    return {
        "notes": [
            {
                "start": round(note["start"] * hop_seconds, 3),
                "end": round(note["end"] * hop_seconds, 3),
                "midi": note["midi"],
                "golden": index in golden,
            }
            for index, note in enumerate(notes)
        ],
        "midi_min": midi_min,
        "midi_max": midi_max,
    }


# --- words.json -----------------------------------------------------------

def parse_lrc(text):
    """Mirrors the client's parser: a line's text is everything after its last
    timestamp, and one line can carry several timestamps (LRC compression),
    each producing its own entry sharing that text."""
    entries = []

    for raw_line in text.splitlines():
        matches = list(TIMESTAMP_PATTERN.finditer(raw_line))
        if not matches:
            continue

        content = raw_line[matches[-1].end():].strip()
        if not content:
            continue

        for match in matches:
            entries.append({"time": _timestamp_seconds(match), "text": content})

    entries.sort(key=lambda entry: entry["time"])
    return entries


def _enhanced_words(text, line_end):
    """Word timings taken verbatim from Enhanced-LRC tags, or None if the line
    has none."""
    matches = list(WORD_TAG_PATTERN.finditer(text))
    if not matches:
        return None

    words = []
    for index, match in enumerate(matches):
        following = matches[index + 1] if index + 1 < len(matches) else None
        word = text[match.end():following.start() if following else len(text)].strip()
        if not word:
            continue

        start = _timestamp_seconds(match)
        end = _timestamp_seconds(following) if following else line_end
        words.append({"w": word, "start": round(start, 3), "end": round(max(end, start), 3)})

    return words or None


def _clip_runs(runs, window_start, window_end):
    clipped = []
    for start, end in runs:
        overlap_start = max(start, window_start)
        overlap_end = min(end, window_end)
        if overlap_end - overlap_start >= MIN_VOICED_RUN_SECONDS:
            clipped.append((overlap_start, overlap_end))
    return clipped


def _estimate_words(words, window_start, window_end, runs):
    """Spreads a line's words over the parts of its window where the stem is
    actually voiced, weighted by word length. Words land on sung audio instead
    of drifting through the silence between phrases."""
    weights = [len(word) + 1 for word in words]
    total_weight = sum(weights)

    if not runs:
        # No voiced audio to go on — fall back to spreading across the whole
        # window, which is what the client does unaided.
        span = window_end - window_start
        timed = []
        cumulative = 0
        for word, weight in zip(words, weights):
            start = window_start + span * cumulative / total_weight
            cumulative += weight
            end = window_start + span * cumulative / total_weight
            timed.append({"w": word, "start": round(start, 3), "end": round(end, 3)})
        return timed

    voiced_total = sum(end - start for start, end in runs)

    def real_time(offset):
        remaining = offset
        for start, end in runs:
            length = end - start
            if remaining <= length:
                return start + remaining
            remaining -= length
        return runs[-1][1]

    timed = []
    cumulative = 0
    for word, weight in zip(words, weights):
        start = real_time(voiced_total * cumulative / total_weight)
        cumulative += weight
        end = real_time(voiced_total * cumulative / total_weight)
        timed.append({"w": word, "start": round(start, 3), "end": round(max(end, start), 3)})
    return timed


def time_words(hop_seconds, voiced, lrc_text):
    """Per-line word timings, or None when the lyrics are unusable."""
    entries = parse_lrc(lrc_text)
    if not entries:
        return None

    total_seconds = len(voiced) * hop_seconds
    runs = [
        (start * hop_seconds, end * hop_seconds)
        for start, end in _index_runs(voiced)
    ]
    runs = [(start, end) for start, end in runs if end - start >= MIN_VOICED_RUN_SECONDS]

    lines = []
    for index, entry in enumerate(entries):
        window_start = entry["time"]
        window_end = entries[index + 1]["time"] if index + 1 < len(entries) else total_seconds
        if window_end <= window_start:
            continue

        enhanced = _enhanced_words(entry["text"], window_end)
        if enhanced:
            lines.append({
                "start": round(enhanced[0]["start"], 3),
                "end": round(enhanced[-1]["end"], 3),
                "words": enhanced,
            })
            continue

        words = entry["text"].split()
        if not words:
            continue

        window_runs = _clip_runs(runs, window_start, window_end)
        timed = _estimate_words(words, window_start, window_end, window_runs)
        # The line ends when singing stops, not when the next line starts —
        # that's what makes the sweep finish with the phrase.
        line_end = window_runs[-1][1] if window_runs else window_end
        lines.append({"start": round(window_start, 3), "end": round(line_end, 3), "words": timed})

    return {"lines": lines} if lines else None


# --- CLI ------------------------------------------------------------------

def write_analysis(hop_seconds, hz, args):
    """Writes whichever of notes.json / words.json were asked for. Word timings
    are optional: without usable lyrics we skip them and exit cleanly, and the
    client falls back to estimating word positions itself."""
    if args.notes_out:
        Path(args.notes_out).write_text(json.dumps(quantize_notes(hop_seconds, hz)))

    if not args.words_out:
        return

    if not args.lrc:
        sys.stderr.write("no --lrc given; skipping word timings\n")
        return

    try:
        lrc_text = Path(args.lrc).read_text(encoding="utf-8")
    except OSError as error:
        sys.stderr.write(f"could not read --lrc: {error}\n")
        return

    payload = time_words(hop_seconds, [value is not None for value in hz], lrc_text)
    if payload is None:
        sys.stderr.write("no usable synced lyrics; skipping word timings\n")
        return

    Path(args.words_out).write_text(json.dumps(payload))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_audio", nargs="?")
    parser.add_argument("instrumental_out", nargs="?")
    parser.add_argument("pitch_out", nargs="?")
    parser.add_argument("--model", default="htdemucs", help="demucs model name")
    parser.add_argument("--vocals-out", help="keep the isolated vocal stem here (wav)")
    parser.add_argument("--notes-out", help="write the quantized note list here")
    parser.add_argument("--words-out", help="write per-word timings here (needs --lrc)")
    parser.add_argument("--lrc", help="file holding the song's synced (LRC) lyrics")
    parser.add_argument("--reanalyze", metavar="PITCH_JSON",
                        help="recompute notes/words from an existing pitch curve, no demucs")
    parser.add_argument("--self-test", action="store_true", help="run the analysis checks and exit")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return

    if args.reanalyze:
        if any([args.input_audio, args.instrumental_out, args.pitch_out]):
            parser.error("--reanalyze takes no positional arguments")

        payload = json.loads(Path(args.reanalyze).read_text())
        write_analysis(payload["hop_seconds"], payload["hz"], args)
        return

    if not all([args.input_audio, args.instrumental_out, args.pitch_out]):
        parser.error("input_audio, instrumental_out and pitch_out are required")

    with tempfile.TemporaryDirectory(prefix="karaoke-separate-") as tmp:
        work_dir = Path(tmp)
        vocals_path, instrumental_path = separate(args.input_audio, args.model, work_dir)

        hop_seconds, hz = extract_pitch(vocals_path)
        Path(args.pitch_out).write_text(json.dumps({"hop_seconds": hop_seconds, "hz": hz}))
        write_analysis(hop_seconds, hz, args)

        if args.vocals_out:
            shutil.move(str(vocals_path), args.vocals_out)
        shutil.move(str(instrumental_path), args.instrumental_out)


# --- Self test ------------------------------------------------------------

def _synthetic_curve():
    """A hand-built pitch curve with a known answer: three sung notes (one of
    them split by a consonant-sized gap), vibrato inside each, and a blip too
    short to count."""
    hz = []

    def silence(seconds):
        hz.extend([None] * int(round(seconds / HOP_SECONDS)))

    def tone(midi, seconds, vibrato=0.3):
        for index in range(int(round(seconds / HOP_SECONDS))):
            wobble = vibrato * math.sin(2 * math.pi * index / 8)
            hz.append(round(440.0 * (2 ** ((midi + wobble - 69) / 12.0)), 2))

    silence(0.5)
    tone(60, 1.0)                       # 0.50 - 1.50
    silence(0.5)
    tone(64, 0.5); silence(0.1); tone(64, 0.5)   # 2.00 - 3.10, merged across the gap
    silence(0.5)
    tone(67, 1.0)                       # 3.60 - 4.60
    silence(0.2)
    tone(72, 0.05)                      # too short to survive
    silence(0.5)

    return HOP_SECONDS, hz


def self_test():
    hop_seconds, hz = _synthetic_curve()

    result = quantize_notes(hop_seconds, hz)
    notes = result["notes"]
    assert [note["midi"] for note in notes] == [60, 64, 67], notes
    assert result["midi_min"] == 60 and result["midi_max"] == 67, result
    assert abs(notes[0]["start"] - 0.5) < 1e-6 and abs(notes[0]["end"] - 1.5) < 1e-6, notes[0]
    assert abs(notes[1]["end"] - notes[1]["start"] - 1.1) < 1e-6, notes[1]
    assert [note["golden"] for note in notes] == [False, False, True], notes
    for previous, following in zip(notes, notes[1:]):
        assert previous["end"] <= following["start"], (previous, following)

    lrc = "[00:00.50] one two three\n[00:02.00] four five\n[00:03.60] six\n"
    words = time_words(hop_seconds, [value is not None for value in hz], lrc)
    lines = words["lines"]
    assert len(lines) == 3, lines
    assert abs(lines[0]["end"] - 1.5) < 1e-6, lines[0]
    assert [word["w"] for word in lines[0]["words"]] == ["one", "two", "three"], lines[0]
    for line in lines:
        for word in line["words"]:
            assert line["start"] - 1e-6 <= word["start"] <= word["end"] <= line["end"] + 1e-6, (line, word)

    enhanced = time_words(
        hop_seconds, [value is not None for value in hz],
        "[00:00.50] <00:00.50> one <00:01.00> two\n[00:02.00] four five\n"
    )
    first = enhanced["lines"][0]
    assert [word["w"] for word in first["words"]] == ["one", "two"], first
    assert abs(first["words"][1]["start"] - 1.0) < 1e-6, first

    assert quantize_notes(hop_seconds, [None] * 40) == {"notes": [], "midi_min": None, "midi_max": None}
    assert time_words(hop_seconds, [False] * 40, "no timestamps here") is None

    sys.stderr.write("karaoke_separate self-test: ok\n")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stdout or "")
        sys.stderr.write(error.stderr or "")
        sys.exit(1)
