// Per-singer scoring against the song's notes.
//
// Every pitch estimate that lands inside a note earns that note some credit;
// when the note is over, its accuracy is how much of it was sung in tune. Lines
// are scored from their notes, and consecutive good lines build a multiplier —
// the shape every karaoke game uses, and the reason a score is worth watching
// rather than a running average that stops moving after ninety seconds.

// Full credit within a third of a semitone, none a semitone and a half out,
// linear between.
const PERFECT_CENTS = 35
const MISS_CENTS = 150
// Wait this long past a note before deciding what it was worth: latency
// estimates are approximate and the last frames of a note still count.
const GRACE_SECONDS = 0.12

const VERDICTS = [
  { name: "perfect", min: 0.9 },
  { name: "great", min: 0.7 },
  { name: "good", min: 0.45 },
  { name: "miss", min: 0 }
]
// A line at Good or better keeps the streak alive.
const COMBO_VERDICTS = new Set([ "perfect", "great", "good" ])
const GRADES = [
  { name: "S", min: 9000 },
  { name: "A", min: 7500 },
  { name: "B", min: 6000 },
  { name: "C", min: 4000 },
  { name: "D", min: 0 }
]
const DISPLAY_SCALE = 10000
// A note counts as "hit" for the results breakdown at half credit.
const HIT_THRESHOLD = 0.5

export function multiplierFor(combo) {
  if (combo >= 6) return 4
  if (combo >= 4) return 3
  if (combo >= 2) return 2
  return 1
}

// How closely one sung frequency matches one target note, 0..1. Folded to the
// nearest octave so a singer in a different register from the original vocal
// isn't punished for it.
export function creditFor(sungHz, targetMidi) {
  if (!sungHz) return 0

  const sungMidi = 69 + 12 * Math.log2(sungHz / 440)
  let cents = (sungMidi - targetMidi) * 100
  cents = ((cents % 1200) + 1200) % 1200
  if (cents > 600) cents -= 1200

  const distance = Math.abs(cents)
  if (distance <= PERFECT_CENTS) return 1
  if (distance >= MISS_CENTS) return 0
  return 1 - (distance - PERFECT_CENTS) / (MISS_CENTS - PERFECT_CENTS)
}

export class SingerScore {
  constructor(melody, singer) {
    this.melody = melody
    this.singer = singer
    this.reset()
  }

  reset() {
    this.notes = this.melody.notes.map(() => ({ frames: 0, credit: 0, done: false, accuracy: 0, scored: true }))
    this.lines = new Map()
    this.lineResults = []
    this.combo = 0
    this.bestCombo = 0
    this.rawScore = 0
    this.cursor = 0
    this.finalizedLine = -1
    this.micLostAt = null
    this.maxRaw = this.melody.perfectRawScore(multiplierFor) || 1
  }

  get score() {
    return Math.round((this.rawScore / this.maxRaw) * DISPLAY_SCALE)
  }

  get multiplier() {
    return multiplierFor(this.combo)
  }

  // Frames arrive roughly in order, so a cursor beats searching. Frames
  // outside every note are ignored rather than penalised — ad-libbing between
  // phrases shouldn't cost anything.
  addFrame(songTime, hz) {
    const notes = this.melody.notes
    while (this.cursor < notes.length && notes[this.cursor].end + GRACE_SECONDS < songTime) this.cursor++

    for (let index = this.cursor; index < notes.length && notes[index].start <= songTime; index++) {
      if (songTime >= notes[index].start && songTime < notes[index].end) {
        const accumulator = this.notes[index]
        accumulator.frames += 1
        accumulator.credit += creditFor(hz, notes[index].midi)
        return
      }
    }
  }

  // Closes out any note or line whose grace window has passed. Returns the
  // line verdicts that just landed, so the stage can pop them.
  advance(songTime) {
    const notes = this.melody.notes
    const verdicts = []

    for (let index = 0; index < notes.length; index++) {
      const note = notes[index]
      if (note.end + GRACE_SECONDS > songTime) break

      const accumulator = this.notes[index]
      if (accumulator.done) continue

      accumulator.done = true
      // Silence with a working mic is a miss; silence because the mic died is
      // not the singer's fault and is left out of their total instead.
      accumulator.accuracy = accumulator.frames > 0 ? accumulator.credit / accumulator.frames : 0
      accumulator.scored = this.micLostAt === null || note.start < this.micLostAt

      const line = this.lines.get(note.lineIndex) || { weight: 0, credit: 0, notes: 0, scored: 0 }
      line.weight += note.weight
      line.credit += accumulator.accuracy * note.weight
      line.notes += 1
      if (accumulator.scored) line.scored += 1
      this.lines.set(note.lineIndex, line)
    }

    // A line is finished once every note after it has started.
    for (const [ lineIndex, line ] of [ ...this.lines.entries() ].sort((a, b) => a[0] - b[0])) {
      if (lineIndex <= this.finalizedLine) continue
      if (this.melody.notesForLine(lineIndex).some((note) => !this.notes[note.index].done)) continue

      this.finalizedLine = lineIndex
      if (line.weight === 0 || line.scored === 0) continue

      const accuracy = line.credit / line.weight
      const verdict = VERDICTS.find((entry) => accuracy >= entry.min).name
      const multiplier = this.multiplier

      this.rawScore += line.credit * 1000 * multiplier
      this.combo = COMBO_VERDICTS.has(verdict) ? this.combo + 1 : 0
      this.bestCombo = Math.max(this.bestCombo, this.combo)
      this.lineResults.push({ lineIndex, accuracy, verdict, combo: this.combo, points: line.credit * 1000 * multiplier, credit: line.credit })
      verdicts.push({ lineIndex, accuracy, verdict, combo: this.combo })
    }

    return verdicts
  }

  // Seeking backwards replays music the scorer has already closed the books
  // on. Without re-opening those notes, everything before the play head stays
  // finalized and the replayed stretch silently scores nothing.
  rewindTo(songTime) {
    const notes = this.melody.notes

    for (let index = 0; index < notes.length; index++) {
      if (notes[index].end + GRACE_SECONDS <= songTime) continue

      this.notes[index] = { frames: 0, credit: 0, done: false, accuracy: 0, scored: true }
    }

    // Lines wholly after the play head are unscored again, and their points
    // come back off the total.
    this.lines.clear()
    const kept = []
    for (const line of this.lineResults) {
      const notesInLine = this.melody.notesForLine(line.lineIndex)
      const endsAfter = notesInLine.some((note) => note.end + GRACE_SECONDS > songTime)
      if (endsAfter) continue

      kept.push(line)
    }

    this.lineResults = kept
    this.rawScore = kept.reduce((sum, line) => sum + line.points, 0)
    this.finalizedLine = kept.length > 0 ? Math.max(...kept.map((line) => line.lineIndex)) : -1
    this.combo = kept.length > 0 ? kept[kept.length - 1].combo : 0
    this.cursor = 0
  }

  // Notes from here on aren't the singer's responsibility.
  markMicLost(songTime) {
    this.micLostAt ??= songTime
  }

  results(timeline) {
    const scored = this.melody.notes.filter((note, index) => this.notes[index].scored)
    const hit = scored.filter((note) => this.notes[note.index].accuracy >= HIT_THRESHOLD)
    const golden = scored.filter((note) => note.golden)
    const weight = scored.reduce((sum, note) => sum + note.weight, 0)
    const credited = scored.reduce((sum, note) => sum + this.notes[note.index].accuracy * note.weight, 0)

    const best = this.lineResults.reduce((top, line) => (!top || line.accuracy > top.accuracy ? line : top), null)
    const bestLine = best && timeline?.lines[best.lineIndex]
      ? { text: timeline.lines[best.lineIndex].text, accuracy: best.accuracy }
      : null

    const score = this.score
    return {
      name: this.singer.name,
      color: this.singer.color,
      score,
      grade: GRADES.find((grade) => score >= grade.min).name,
      accuracy: weight > 0 ? credited / weight : 0,
      notesHit: hit.length,
      notesTotal: scored.length,
      goldenHit: golden.filter((note) => this.notes[note.index].accuracy >= HIT_THRESHOLD).length,
      goldenTotal: golden.length,
      bestCombo: this.bestCombo,
      bestLine,
      lineAccuracies: this.lineResults.map((line) => line.accuracy),
      micLostAt: this.micLostAt
    }
  }
}
