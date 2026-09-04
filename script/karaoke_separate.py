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
        [--model htdemucs] [--device cuda] [--vocals-out out.wav]
        [--notes-out notes.json] [--words-out words.json] [--lrc lyrics.lrc]

    python karaoke_separate.py --reanalyze pitch.json --notes-out notes.json
        [--words-out words.json --lrc lyrics.lrc]

    python karaoke_separate.py --reextract vocals.mp3 --pitch-out pitch.json
        [--notes-out notes.json --words-out words.json --lrc lyrics.lrc]
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
# pyin is also strictly monophonic: a refrain sung in stacked harmonies reads
# as "unvoiced" at full volume, and whole sections used to have nothing to
# sing. Frames that are loud but unvoiced get a second opinion from plain YIN
# (which always answers), kept only for runs at least this long — singing is
# sustained, noise is not.
RESCUE_MIN_SECONDS = 0.3

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
# This many consecutive fenced-out notes that cohere an octave up or down is a
# register change worth keeping, not scattered tracker junk (see
# reject_pitch_outliers).
OUTLIER_RESCUE_MIN_NOTES = 4
# Voiced blips shorter than this are ignored when deciding where a line's words
# actually land in time.
MIN_VOICED_RUN_SECONDS = 0.05

# --- Singing-window fence -------------------------------------------------
# Demucs puts a lead instrument in the same register as the voice into the
# *vocal* stem — a pan flute, a sax, a lead synth — and everything downstream
# then treats it as melody. On K3's "Oya Lélé" a fifteen-second pan-flute break
# arrived as 37 fast ornamented notes: the guide melody played them (so the
# song sounded like a flute solo rather than a tune to sing), the pitch lane
# drew them, and — worst of the three — they counted towards the perfect score
# the singer is marked against, so a flawless performance could not reach it.
#
# The lyrics know better than the stem does. A line's words say roughly how
# long it takes to sing, so anything voiced well past that is not the singer.
# The budget is deliberately loose — it exists to catch a break measured in
# seconds, not to trim the tail off a held note.
NOTE_WINDOW_SECONDS_PER_CHAR = 0.25
# Even "Oh" gets this long, so a short exclamation held over a bar survives.
NOTE_WINDOW_MIN_SECONDS = 3.0
# A note may lead its line slightly (the tracker hears the onset first) and run
# slightly past the budget.
NOTE_WINDOW_LEAD_SECONDS = 0.3
NOTE_WINDOW_TAIL_SECONDS = 0.5

TIMESTAMP_PATTERN = re.compile(r"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]")
# Enhanced LRC ("A2") word timings, e.g. "[00:12.30] <00:12.30> Hello <00:12.80> from".
WORD_TAG_PATTERN = re.compile(r"<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>")
# Duet markers some lyric sources put in front of a line ("v1:", "F:").
# Mirrors the client's SINGER_PREFIX_PATTERN: the displayed text drops the
# marker, so a timed word carrying it would skew the sweep across the line.
SINGER_PREFIX_PATTERN = re.compile(r"^\s*\[?(?:v1|v2|m|f|male|female|duet|both)\]?\s*[:.]\s*", re.IGNORECASE)


# --- Separation & pitch extraction ---------------------------------------

def separate(input_path, model, work_dir, device=None):
    # demucs picks its own device when told nothing, which on a CPU-only box is
    # the only choice anyway. Naming one matters where there is something better
    # to name: the same song is ~205s on prod's CPU and ~38s on an M4 via mps,
    # so the GPU offload passes "cuda" through to here.
    device_options = ["-d", device] if device else []
    subprocess.run(
        [sys.executable, "-m", "demucs", "--two-stems", "vocals", "-n", model,
         *device_options, "-o", str(work_dir), str(input_path)],
        check=True, capture_output=True, text=True,
    )

    stem_dir = work_dir / model / Path(input_path).stem
    return stem_dir / "vocals.wav", stem_dir / "no_vocals.wav"


# A reference melody as (time, frequency) pairs, one per hop; frequency is
# None for instrumental gaps / unvoiced frames the singer has nothing to
# match. Downstream (the browser) compares its own live pitch estimate
# against the point nearest the current playback time.
def extract_pitch(vocals_path):
    import librosa  # imported lazily: --reanalyze doesn't need it

    y, sr = librosa.load(vocals_path, sr=None, mono=True)
    hop_length = max(1, round(sr * HOP_SECONDS))

    f0, voiced_flag, _voiced_prob = librosa.pyin(
        y, fmin=librosa.note_to_hz(FMIN_NOTE), fmax=librosa.note_to_hz(FMAX_NOTE), sr=sr, hop_length=hop_length
    )

    # Anything this quiet is separation residue, not the singer.
    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=hop_length)[0]
    gate = float(np.percentile(rms, 99)) * SILENCE_RATIO
    loud = np.resize(rms > gate, len(f0))

    voiced = np.array([bool(flag) and not np.isnan(value) for flag, value in zip(voiced_flag, f0)])
    rescued = rescue_harmonized(y, sr, hop_length, voiced, loud)

    hz = []
    for index, value in enumerate(f0):
        if voiced[index] and loud[index]:
            hz.append(round(float(value), 2))
        elif index in rescued:
            hz.append(round(rescued[index], 2))
        else:
            hz.append(None)
    return hop_length / sr, hz


def rescue_harmonized(y, sr, hop_length, voiced, loud):
    """Frames pyin refused (its HMM is monophonic — stacked harmonies read as
    unvoiced at any volume) but that are clearly loud, re-estimated with plain
    YIN. Only sustained runs qualify; YIN's mistakes on the rest are jittery
    and get cleaned up by the median filter, the minimum note length and the
    octave fence downstream."""
    import librosa

    min_frames = max(1, round(RESCUE_MIN_SECONDS * sr / hop_length))
    runs = [(start, end) for start, end in _index_runs(loud & ~voiced) if end - start >= min_frames]
    if not runs:
        return {}

    yin = librosa.yin(
        y, fmin=librosa.note_to_hz(FMIN_NOTE), fmax=librosa.note_to_hz(FMAX_NOTE), sr=sr, hop_length=hop_length
    )

    rescued = {}
    for start, end in runs:
        for index in range(start, min(end, len(yin))):
            value = float(yin[index])
            if math.isfinite(value) and value > 0:
                rescued[index] = value
    return rescued


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
    distribution — the octave errors and rumble pyin leaves behind.

    Octave-aware: junk is scattered, singing is contiguous. A run of
    consecutive fenced-out notes that all land inside the fence under one
    whole-octave shift is a register change (a falsetto chorus, a dropped
    verse), not tracker noise, and is kept — scoring folds octaves anyway,
    and the lane maps whatever range survives."""
    if len(notes) < MIN_NOTES_FOR_OUTLIER_REJECTION:
        return notes

    pitches = np.array([note["midi"] for note in notes], dtype=float)
    q1, q3 = np.percentile(pitches, [25, 75])
    spread = (q3 - q1) * OUTLIER_IQR_MULTIPLIER
    low, high = q1 - spread, q3 + spread

    keep = [low <= pitch <= high for pitch in pitches]
    for start, end in _index_runs([not kept for kept in keep]):
        if end - start < OUTLIER_RESCUE_MIN_NOTES:
            continue

        segment = pitches[start:end]
        if any(
            all(low <= pitch + shift <= high for pitch in segment)
            for shift in (-12, 12, -24, 24)
        ):
            keep[start:end] = [True] * (end - start)

    kept = [note for note, keeping in zip(notes, keep) if keeping]
    # Never hand back an empty melody because the distribution was degenerate
    # (every note on one pitch makes the fence zero-width).
    return kept if kept else notes


def quantize_notes(hop_seconds, hz, windows=None):
    """The sung melody as discrete notes: {notes: [{start, end, midi, golden}],
    midi_min, midi_max}. Empty notes are a legal result (rap, spoken word, a
    stem pyin can't track) — the client hides the pitch lane.

    windows, when given, is where the lyrics say singing happens; notes outside
    it are instrument bleed and are dropped (see singing_windows)."""
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
    # Before the range and the golden picks are taken, not after: a flute break
    # left in would set the top of the pitch lane and win the golden decile
    # with notes that are then dropped from under both.
    notes = fence_notes_to_singing(notes, windows, hop_seconds)
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


def singing_windows(lrc_text, total_seconds):
    """When the lyrics say somebody is singing: one (start, end) per LRC line,
    each capped at what its own words could plausibly take. None when there are
    no usable lyrics to fence against."""
    entries = parse_lrc(lrc_text)
    if not entries:
        return None

    windows = []
    for index, entry in enumerate(entries):
        start = entry["time"]
        next_start = entries[index + 1]["time"] if index + 1 < len(entries) else total_seconds
        budget = max(NOTE_WINDOW_MIN_SECONDS, len(entry["text"]) * NOTE_WINDOW_SECONDS_PER_CHAR)
        end = min(next_start, start + budget)
        if end <= start:
            continue

        windows.append((start - NOTE_WINDOW_LEAD_SECONDS, end + NOTE_WINDOW_TAIL_SECONDS))

    return windows or None


def fence_notes_to_singing(notes, windows, hop_seconds):
    """Drops notes whose midpoint falls where no line is being sung. Midpoint
    rather than overlap: a note straddling the edge of a window belongs to
    whichever side it mostly sits on. Notes are still in frame indices here,
    which is why the hop is needed to compare them against the lyrics' clock."""
    if not windows:
        return notes

    kept = []
    cursor = 0
    for note in notes:
        middle = (note["start"] + note["end"]) / 2 * hop_seconds
        while cursor < len(windows) and windows[cursor][1] < middle:
            cursor += 1
        if cursor < len(windows) and windows[cursor][0] <= middle:
            kept.append(note)

    return kept


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


def _strip_singer_prefix(words):
    """The duet marker is display metadata, not a sung word. Dropped whole
    when it stands alone, trimmed off when it's glued to the first word."""
    if not words:
        return words

    first = SINGER_PREFIX_PATTERN.sub("", words[0]["w"], count=1).strip()
    if not first:
        return words[1:]
    if first != words[0]["w"]:
        return [dict(words[0], w=first)] + words[1:]
    return words


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

    return _strip_singer_prefix(words) or None


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
        next_start = entries[index + 1]["time"] if index + 1 < len(entries) else total_seconds
        # Capped by what the line's own words could take, for the same reason
        # the notes are (see singing_windows). "Oh jee" in front of a fifteen
        # second flute break was stretched across the whole of it, one syllable
        # lasting 8.25s, because the stem stayed "voiced" throughout.
        budget = max(NOTE_WINDOW_MIN_SECONDS, len(entry["text"]) * NOTE_WINDOW_SECONDS_PER_CHAR)
        window_end = min(next_start, window_start + budget)
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

        words = SINGER_PREFIX_PATTERN.sub("", entry["text"], count=1).split()
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
    lrc_text = None
    if args.lrc:
        try:
            lrc_text = Path(args.lrc).read_text(encoding="utf-8")
        except OSError as error:
            sys.stderr.write(f"could not read --lrc: {error}\n")

    if args.notes_out:
        # Without lyrics there is nothing to fence against and every note is
        # kept, which is the behaviour every song had before the fence existed.
        windows = singing_windows(lrc_text, len(hz) * hop_seconds) if lrc_text else None
        Path(args.notes_out).write_text(json.dumps(quantize_notes(hop_seconds, hz, windows)))

    if not args.words_out:
        return

    if lrc_text is None:
        sys.stderr.write("no --lrc given; skipping word timings\n")
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
    parser.add_argument("--device", help="torch device for demucs (cuda, mps, cpu); demucs decides if omitted")
    parser.add_argument("--vocals-out", help="keep the isolated vocal stem here (wav)")
    parser.add_argument("--notes-out", help="write the quantized note list here")
    parser.add_argument("--words-out", help="write per-word timings here (needs --lrc)")
    parser.add_argument("--lrc", help="file holding the song's synced (LRC) lyrics")
    parser.add_argument("--reanalyze", metavar="PITCH_JSON",
                        help="recompute notes/words from an existing pitch curve, no demucs")
    parser.add_argument("--reextract", metavar="VOCALS_AUDIO",
                        help="recompute the pitch curve from an existing vocal stem, no demucs")
    parser.add_argument("--pitch-out", dest="reextract_pitch_out",
                        help="where --reextract writes the refreshed pitch curve")
    args = parser.parse_args()

    if args.reanalyze:
        if any([args.input_audio, args.instrumental_out, args.pitch_out]):
            parser.error("--reanalyze takes no positional arguments")

        payload = json.loads(Path(args.reanalyze).read_text())
        write_analysis(payload["hop_seconds"], payload["hz"], args)
        return

    # Cheaper than a separation, dearer than a reanalysis: pyin over the kept
    # stem. This is how caches predating a pitch-extraction improvement pick
    # it up without paying for demucs again.
    if args.reextract:
        if any([args.input_audio, args.instrumental_out, args.pitch_out]):
            parser.error("--reextract takes no positional arguments")
        if not args.reextract_pitch_out:
            parser.error("--reextract needs --pitch-out")

        hop_seconds, hz = extract_pitch(args.reextract)
        Path(args.reextract_pitch_out).write_text(json.dumps({"hop_seconds": hop_seconds, "hz": hz}))
        write_analysis(hop_seconds, hz, args)
        return

    if not all([args.input_audio, args.instrumental_out, args.pitch_out]):
        parser.error("input_audio, instrumental_out and pitch_out are required")

    with tempfile.TemporaryDirectory(prefix="karaoke-separate-") as tmp:
        work_dir = Path(tmp)
        vocals_path, instrumental_path = separate(args.input_audio, args.model, work_dir, args.device)

        hop_seconds, hz = extract_pitch(vocals_path)
        Path(args.pitch_out).write_text(json.dumps({"hop_seconds": hop_seconds, "hz": hz}))
        write_analysis(hop_seconds, hz, args)

        if args.vocals_out:
            shutil.move(str(vocals_path), args.vocals_out)
        shutil.move(str(instrumental_path), args.instrumental_out)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stdout or "")
        sys.stderr.write(error.stderr or "")
        sys.exit(1)
