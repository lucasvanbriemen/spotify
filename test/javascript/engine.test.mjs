// Engine tests: the count-in's GO beat, the alignment offset, and the guide
// melody's register transposition. Run with `node --test test/javascript`.
import { test } from "node:test"
import assert from "node:assert/strict"

// The engine loop runs on requestAnimationFrame; here each frame is pumped by
// hand.
let pendingFrame = null
globalThis.requestAnimationFrame = (callback) => { pendingFrame = callback; return 1 }
globalThis.cancelAnimationFrame = () => { pendingFrame = null }

const { KaraokeEngine } = await import("karaoke/engine")
const { LyricsTimeline } = await import("karaoke/lyrics_timing")
const { Melody } = await import("karaoke/melody")

function pump() {
  const callback = pendingFrame
  pendingFrame = null
  callback?.()
}

function fakeAudioParam() {
  const calls = []
  return {
    value: 0,
    calls,
    setValueAtTime(value, at) { calls.push([ "set", value, at ]) },
    setTargetAtTime(value, at) { calls.push([ "target", value, at ]) },
    linearRampToValueAtTime(value, at) { calls.push([ "ramp", value, at ]) },
    cancelScheduledValues() { calls.push([ "cancel" ]) }
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
  }

  songTimeAt() { return null }
  contextTimeFor(songTime) { return songTime }
}

const fakeSettings = {
  get(key) { return ({ latencyTrimMs: 0, vocalGuidePercent: 0, guideMelody: false })[key] },
  displayOffsetSeconds() { return 0 },
  scoringOffsetSeconds() { return 0 }
}

// Captures what the engine handed the view each frame (the state object is
// reused, so the countIn has to be copied).
function fakeView() {
  return {
    countIn: undefined,
    time: undefined,
    setLines() {},
    setNotes() {},
    frame(state) {
      this.time = state.time
      this.countIn = state.countIn ? { ...state.countIn } : null
    }
  }
}

// First line at 3s; long break before the line at 20s.
const LRC = [ "[00:03.00] Hello world", "[00:06.00] Second line", "[00:20.00] After the break" ].join("\n")

function engineAt() {
  const transport = new FakeTransport()
  const view = fakeView()
  const engine = new KaraokeEngine({ transport, settings: fakeSettings, view })
  engine.loadSong({ timeline: LyricsTimeline.parse(LRC), melody: Melody.empty(), singers: [] })
  engine.start()
  return { engine, transport, view }
}

function countInAt(setup, time) {
  setup.transport.currentTime = time
  pump()
  return setup.view.countIn
}

test("the initial count-in runs 3-2-1 and then holds a GO beat instead of vanishing", () => {
  const setup = engineAt()

  assert.equal(countInAt(setup, 0.2).digit, 3)
  assert.equal(countInAt(setup, 1.5).digit, 2)
  assert.equal(countInAt(setup, 2.4).digit, 1)

  const go = countInAt(setup, 3.2)
  assert.equal(go.kind, "initial")
  assert.equal(go.digit, 0)

  assert.equal(countInAt(setup, 3.9), null) // GO window over
  setup.engine.stop()
})

test("a line without a count-in gets no GO beat", () => {
  const setup = engineAt()
  // The second line follows the first with under 2s of silence.
  assert.equal(countInAt(setup, 6.2), null)
  setup.engine.stop()
})

test("the gap cue counts down in dots and ends on digit 0", () => {
  const setup = engineAt()

  const during = countInAt(setup, 18.5)
  assert.equal(during.kind, "gap")
  assert.equal(during.digit, 2)

  const go = countInAt(setup, 20.3)
  assert.equal(go.kind, "gap")
  assert.equal(go.digit, 0)

  assert.equal(countInAt(setup, 21.0), null)
  setup.engine.stop()
})

test("the alignment offset shifts the display clock", () => {
  const setup = engineAt()
  setup.engine.setAlignmentOffset(0.5)

  setup.transport.currentTime = 3.4
  pump()
  // 3.4 on the file clock is 2.9 on the lyric clock: still counting in.
  assert.equal(Math.round(setup.view.time * 10) / 10, 2.9)
  assert.equal(setup.view.countIn.digit, 1)
  setup.engine.stop()
})

test("the guide melody is transposed towards the singer's register in whole octaves", () => {
  const transport = new FakeTransport()
  const engine = new KaraokeEngine({ transport, settings: fakeSettings, view: fakeView() })

  const melody = Melody.parse(
    { notes: [ { start: 1, end: 2, midi: 62 }, { start: 2, end: 3, midi: 64 }, { start: 3, end: 4, midi: 65 } ] },
    LyricsTimeline.parse(LRC)
  )

  engine.loadSong({
    timeline: LyricsTimeline.parse(LRC),
    melody,
    singers: [ { name: "Bass", color: "#000", registerMidi: 50, deviceId: null } ]
  })
  assert.equal(engine.guide.transpose, -12)

  // No register measured -> no transposition.
  engine.loadSong({
    timeline: LyricsTimeline.parse(LRC),
    melody,
    singers: [ { name: "Unknown", color: "#000", registerMidi: null, deviceId: null } ]
  })
  assert.equal(engine.guide.transpose, 0)
})
