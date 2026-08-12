// The song's melody as discrete notes (notes.json), prepared for drawing and
// scoring: each note tied to the lyric line it belongs to, and weighted for
// what hitting it is worth.
//
// A song with no usable melody — rap, spoken word, anything the pitch tracker
// couldn't follow — produces an empty Melody, and the stage simply has no
// pitch lane and falls back to scoring against the raw pitch curve.

// Golden notes are worth double.
const GOLDEN_MULTIPLIER = 2
// Without server-side golden flags, the longest tenth of the notes stand in.
const GOLDEN_FRACTION = 0.1
// A little headroom above and below so the outermost notes aren't drawn on
// the edge of the lane.
const LANE_PADDING_SEMITONES = 2

export class Melody {
  constructor(notes, midiMin, midiMax) {
    this.notes = notes
    this.midiMin = midiMin
    this.midiMax = midiMax
  }

  static empty() {
    return new Melody([], 60, 72)
  }

  // payload is notes.json; timeline supplies the lyric lines to attach to.
  static parse(payload, timeline) {
    const raw = payload?.notes || []
    if (raw.length === 0) return Melody.empty()

    const hasFlags = raw.some((note) => note.golden)
    const goldenCutoff = hasFlags ? null : durationCutoff(raw, GOLDEN_FRACTION)

    const notes = raw.map((note, index) => {
      const duration = Math.max(0, note.end - note.start)
      const golden = hasFlags ? Boolean(note.golden) : duration >= goldenCutoff

      return {
        index,
        start: note.start,
        end: note.end,
        midi: note.midi,
        golden,
        duration,
        // What the note is worth: how long it is, doubled when it's golden.
        weight: duration * (golden ? GOLDEN_MULTIPLIER : 1),
        lineIndex: lineFor(note, timeline)
      }
    })

    const midiMin = Math.min(...notes.map((note) => note.midi)) - LANE_PADDING_SEMITONES
    const midiMax = Math.max(...notes.map((note) => note.midi)) + LANE_PADDING_SEMITONES

    return new Melody(notes, midiMin, midiMax)
  }

  get isEmpty() {
    return this.notes.length === 0
  }

  // Where the melody lives, register-wise — what the guide melody's octave
  // shift is measured against.
  get medianMidi() {
    if (this.isEmpty) return null

    const sorted = this.notes.map((note) => note.midi).sort((a, b) => a - b)
    return sorted[(sorted.length - 1) >> 1]
  }

  get lineCount() {
    return this.notes.reduce((highest, note) => Math.max(highest, note.lineIndex + 1), 0)
  }

  notesForLine(lineIndex) {
    return this.notes.filter((note) => note.lineIndex === lineIndex)
  }

  // Everything overlapping a time window, for drawing the lane. Binary search
  // for the first candidate, then walk — the lane is redrawn every frame.
  notesInWindow(from, to) {
    const notes = this.notes
    let low = 0
    let high = notes.length

    while (low < high) {
      const middle = (low + high) >> 1
      if (notes[middle].end < from) low = middle + 1
      else high = middle
    }

    const visible = []
    for (let index = low; index < notes.length && notes[index].start <= to; index++) {
      if (notes[index].end >= from) visible.push(notes[index])
    }
    return visible
  }

  // What a flawless run of this song is worth, so two singers on any song can
  // be shown on the same 0..10000 scale. Combo multipliers ramp exactly as
  // they would in a real performance.
  perfectRawScore(multiplierFor) {
    const byLine = new Map()
    for (const note of this.notes) {
      byLine.set(note.lineIndex, (byLine.get(note.lineIndex) || 0) + note.weight)
    }

    let combo = 0
    let raw = 0
    for (const lineIndex of [ ...byLine.keys() ].sort((a, b) => a - b)) {
      raw += byLine.get(lineIndex) * 1000 * multiplierFor(combo)
      combo += 1
    }
    return raw
  }
}

// The line a note belongs to is whichever it overlaps most; a note in an
// instrumental break attaches to the nearest line by midpoint.
function lineFor(note, timeline) {
  const lines = timeline?.lines || []
  if (lines.length === 0) return 0

  let bestIndex = 0
  let bestOverlap = -1

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]
    const overlap = Math.min(note.end, line.endTime) - Math.max(note.start, line.time)
    if (overlap > bestOverlap) {
      bestOverlap = overlap
      bestIndex = index
    }
  }

  if (bestOverlap > 0) return bestIndex

  const middle = (note.start + note.end) / 2
  let nearest = 0
  let nearestDistance = Infinity
  lines.forEach((line, index) => {
    const distance = Math.abs((line.time + line.endTime) / 2 - middle)
    if (distance < nearestDistance) {
      nearestDistance = distance
      nearest = index
    }
  })
  return nearest
}

function durationCutoff(notes, fraction) {
  const durations = notes.map((note) => note.end - note.start).sort((a, b) => b - a)
  const position = Math.max(0, Math.ceil(durations.length * fraction) - 1)
  return durations[position]
}
