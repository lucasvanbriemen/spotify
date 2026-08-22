// Two singers on one microphone.
//
// A receiver that mixes its two mics (the JBL PartyBox wireless set, for one)
// hands the browser a single summed signal, so the audio cannot tell the
// singers apart. The lyrics can: a duet marks who takes which line. These
// tests pin the two things that make that work — per-singer line ownership in
// the scorer, and the engine handing one mic's frames to both singers.
import { test } from "node:test"
import assert from "node:assert/strict"

let pendingFrame = null
globalThis.requestAnimationFrame = (callback) => { pendingFrame = callback; return 1 }
globalThis.cancelAnimationFrame = () => { pendingFrame = null }

const { KaraokeEngine } = await import("karaoke/engine")
const { LyricsTimeline } = await import("karaoke/lyrics_timing")
const { Melody } = await import("karaoke/melody")
const { SingerScore, multiplierFor } = await import("karaoke/scoring")

function pump() {
  const callback = pendingFrame
  pendingFrame = null
  callback?.()
}

// v1 takes lines 0 and 2, v2 takes line 1, and the last line is "both".
const DUET_LRC = [
  "[00:00.00] v1: my line",
  "[00:01.00] v2: your line",
  "[00:02.00] v1: mine again",
  "[00:03.00] both: together now"
].join("\n")

// One note per second, each landing squarely inside its line.
const NOTES = {
  notes: [ 0, 1, 2, 3 ].map((second) => ({ start: second + 0.1, end: second + 0.9, midi: 60 }))
}

function duetMelody() {
  return Melody.parse(NOTES, LyricsTimeline.parse(DUET_LRC))
}

function ownershipFor(part, timeline) {
  return (lineIndex) => {
    const marked = timeline.lines[lineIndex]?.singer ?? null
    return marked === null || marked === part
  }
}

test("the lyric parser assigns duet markers to parts, and leaves 'both' unassigned", () => {
  const lines = LyricsTimeline.parse(DUET_LRC).lines

  assert.deepEqual(lines.map((line) => line.singer), [ 1, 2, 1, null ])
  // The marker itself is not sung, so it must not survive into the words.
  assert.equal(lines[0].text, "my line")
  assert.equal(lines[3].text, "together now")
})

test("each note is attached to the line it lands in", () => {
  assert.deepEqual(duetMelody().notes.map((note) => note.lineIndex), [ 0, 1, 2, 3 ])
})

test("a singer's perfect score counts only their own lines, plus the shared one", () => {
  const melody = duetMelody()
  const timeline = LyricsTimeline.parse(DUET_LRC)

  const whole = melody.perfectRawScore(multiplierFor)
  const first = melody.perfectRawScore(multiplierFor, ownershipFor(1, timeline))
  const second = melody.perfectRawScore(multiplierFor, ownershipFor(2, timeline))

  // Singer 1 owns three of the four lines, singer 2 owns two — both strictly
  // less than the whole song, which is the point: scoring a singer against
  // lines they never sing caps them well below 10000.
  assert.ok(first < whole, "singer 1's perfect run must be less than the whole song")
  assert.ok(second < first, "singer 2 owns fewer lines than singer 1")
  assert.ok(second > 0)
})

test("a singer who sings only their own lines still scores full marks", () => {
  const melody = duetMelody()
  const timeline = LyricsTimeline.parse(DUET_LRC)
  const score = new SingerScore(melody, { name: "A" }, ownershipFor(1, timeline))

  // Sing dead-on through every note of the song, including the other singer's.
  for (const note of melody.notes) {
    for (let t = note.start; t < note.end; t += 0.05) score.addFrame(t, 440 * 2 ** ((60 - 69) / 12))
  }
  score.advance(10)

  assert.equal(score.score, 10000, "own lines sung perfectly should be a perfect score")
})

test("the other singer's lines never break your combo", () => {
  const melody = duetMelody()
  const timeline = LyricsTimeline.parse(DUET_LRC)
  const score = new SingerScore(melody, { name: "A" }, ownershipFor(1, timeline))
  const inTune = 440 * 2 ** ((60 - 69) / 12)

  // Sings lines 0, 2 and 3 (theirs) and stays silent through line 1 (not
  // theirs). A silent line of their own would reset the combo to 0.
  for (const note of melody.notes) {
    if (note.lineIndex === 1) continue
    for (let t = note.start; t < note.end; t += 0.05) score.addFrame(t, inTune)
  }
  score.advance(10)

  assert.equal(score.combo, 3, "three owned lines sung, none missed")
  assert.equal(score.score, 10000)
})

test("singing over the other singer's line earns nothing and costs nothing", () => {
  const melody = duetMelody()
  const timeline = LyricsTimeline.parse(DUET_LRC)
  const score = new SingerScore(melody, { name: "B" }, ownershipFor(2, timeline))

  // Only sings on line 0, which belongs to singer 1.
  const note = melody.notes[0]
  for (let t = note.start; t < note.end; t += 0.05) score.addFrame(t, 440)
  score.advance(1.5)

  assert.equal(score.score, 0, "credit on someone else's line must not count")
  assert.equal(score.combo, 0, "and must not build a combo either")
})

test("results leave the other singer's notes out of the totals", () => {
  const melody = duetMelody()
  const timeline = LyricsTimeline.parse(DUET_LRC)
  const score = new SingerScore(melody, { name: "B" }, ownershipFor(2, timeline))
  score.advance(10)

  // Singer 2 owns line 1 and the shared line 3 — two notes of the four.
  assert.equal(score.results(timeline).notesTotal, 2)
})

// --- The shared microphone ------------------------------------------------

class FakeMic extends EventTarget {
  constructor() {
    super()
    this.level = 0.5
    this.frames = []
    this.drains = 0
  }

  push(frame) { this.frames.push(frame) }

  drainFrames() {
    this.drains += 1
    const frames = this.frames
    this.frames = []
    return frames
  }
}

// Enough of an AudioContext for the guide-melody synth the engine builds in
// its constructor; none of it makes a sound here.
function fakeAudioParam() {
  return {
    value: 0,
    setValueAtTime() {},
    setTargetAtTime() {},
    linearRampToValueAtTime() {},
    cancelScheduledValues() {}
  }
}

function fakeContext() {
  return {
    currentTime: 0,
    createGain() { return { gain: fakeAudioParam(), connect() {}, disconnect() {} } },
    createOscillator() {
      return { type: "", frequency: fakeAudioParam(), connect() {}, disconnect() {}, start() {}, stop() {} }
    }
  }
}

class FakeTransport extends EventTarget {
  constructor() {
    super()
    this.context = fakeContext()
    this.output = {}
    this.currentTime = 0
    this.duration = 300
    this.playing = true
  }

  // Mic frames are stamped on the audio clock; here it is the song clock too.
  songTimeAt(t) { return t }
  contextTimeFor(songTime) { return songTime }
}

const fakeSettings = {
  get(key) { return ({ latencyTrimMs: 0, vocalGuidePercent: 0, guideMelody: false })[key] },
  displayOffsetSeconds() { return 0 },
  scoringOffsetSeconds() { return 0 }
}

function sharedMicEngine() {
  const transport = new FakeTransport()
  const view = { setLines() {}, setNotes() {}, frame() {} }
  const engine = new KaraokeEngine({ transport, settings: fakeSettings, view })
  const timeline = LyricsTimeline.parse(DUET_LRC)

  engine.loadSong({
    timeline,
    melody: Melody.parse(NOTES, timeline),
    // Both singers read mic 0 — one input between them.
    singers: [
      { name: "A", micIndex: 0, part: 1 },
      { name: "B", micIndex: 0, part: 2 }
    ]
  })

  const mic = new FakeMic()
  engine.setMics([ mic ])
  engine.start()
  return { engine, transport, mic }
}

// The trap: drainFrames() empties the buffer, so a per-singer drain would hand
// singer 1 every frame and singer 2 an empty list — scoring them a silent zero
// no matter how well they sang.
test("one microphone feeding two singers is drained once and shared", () => {
  const { engine, transport, mic } = sharedMicEngine()
  const inTune = 440 * 2 ** ((60 - 69) / 12)

  // A frame inside line 1's note, which belongs to singer 2.
  mic.push({ t: 1.5, hz: inTune, rms: 0.2 })
  transport.currentTime = 1.6
  pump()

  assert.equal(mic.drains, 1, "the mic must be drained exactly once per frame")

  // Run past the end so every line is finalized.
  transport.currentTime = 10
  pump()

  const [ first, second ] = engine.results()
  assert.equal(second.name, "B")
  assert.ok(second.score > 0, "singer 2 must be credited for the line they sang")
  assert.equal(first.score, 0, "singer 1 sang nothing on their own lines")

  engine.stop()
})

// The mic is bound at index 0 and singer 2 sits at index 1, so a handler that
// only marked scores[micIndex] would leave singer 2 being blamed for every
// silent note after the mic died.
test("losing a shared microphone ends scoring for both singers, not just the first", () => {
  const { engine, transport, mic } = sharedMicEngine()

  transport.currentTime = 1.0
  pump()
  mic.dispatchEvent(new CustomEvent("ended"))

  transport.currentTime = 10
  pump()

  const [ first, second ] = engine.results()

  // Notes that were live while the mic still worked stay the singer's own:
  // singer 1's line 0 starts at 0.1s, before the loss at 1.0s.
  assert.equal(first.notesTotal, 1, "only the note that played before the mic died counts")
  // Everything singer 2 owns starts after the loss, so none of it is theirs —
  // which is only true if the loss reached their scorer at all.
  assert.equal(second.notesTotal, 0, "singer 2 must not be blamed for a mic that died before their line")

  engine.stop()
})
