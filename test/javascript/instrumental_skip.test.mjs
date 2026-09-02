// Skipping the stretches of a song with nothing to sing.
//
// A two-minute outro or an eight-bar solo leaves a room standing at the
// microphone watching a progress bar, so past INSTRUMENTAL_SKIP_SECONDS the
// engine moves the play head on and leaves just enough of the break for the
// count-in to land in. These tests pin where it cuts to, and — just as
// important — where it leaves the song alone.
import { test } from "node:test"
import assert from "node:assert/strict"

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
  return {
    value: 0,
    setValueAtTime() {}, setTargetAtTime() {}, linearRampToValueAtTime() {}, cancelScheduledValues() {}
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
  constructor(duration = 200) {
    super()
    this.context = fakeContext()
    this.output = {}
    this.currentTime = 0
    this.duration = duration
    this.playing = true
    this.seeks = []
  }

  songTimeAt() { return null }
  contextTimeFor(songTime) { return songTime }

  seek(seconds) {
    this.seeks.push(seconds)
    this.currentTime = Math.min(seconds, this.duration)
    this.dispatchEvent(new CustomEvent("seeked", { detail: { time: this.currentTime } }))
  }
}

function fakeSettings(overrides = {}) {
  return {
    get(key) { return ({ latencyTrimMs: 0, vocalGuidePercent: 0, guideMelody: false, ...overrides })[key] },
    displayOffsetSeconds() { return 0 },
    scoringOffsetSeconds() { return 0 }
  }
}

// A 40s intro, a two-second breath, a 30s solo, then the last line — with the
// file running on for another minute after it.
const LRC = [
  "[00:40.00] First line after the intro",
  "[00:44.00] Second line",
  "[01:16.00] After the solo",
  "[01:20.00] The last line"
].join("\n")

function engineOn(lrc = LRC, { settings = fakeSettings(), duration = 200 } = {}) {
  const transport = new FakeTransport(duration)
  const engine = new KaraokeEngine({ transport, settings, view: { setLines() {}, setNotes() {}, frame() {} } })
  engine.loadSong({ timeline: LyricsTimeline.parse(lrc), melody: Melody.empty(), singers: [] })
  engine.start()
  return { engine, transport }
}

function at(setup, time) {
  setup.transport.currentTime = time
  pump()
  return setup.transport.seeks
}

test("a long intro is skipped to just before the first line", () => {
  const setup = engineOn()

  assert.deepEqual(at(setup, 0.5), [ 36 ], "40s of intro leaves the four-second lead-in")
  setup.engine.stop()
})

test("the skip lands past its own target, so the next frame doesn't skip again", () => {
  const setup = engineOn()

  at(setup, 0.5)
  pump() // the frame straight after the cut, reading the clock the seek set
  pump()

  assert.equal(setup.transport.seeks.length, 1)
  setup.engine.stop()
})

test("a long instrumental break mid-song is skipped, a short one is not", () => {
  const setup = engineOn()

  // Between line 2 (ends ~48s) and line 3 (76s): a 28-second solo.
  assert.deepEqual(at(setup, 50), [ 72 ])
  setup.engine.stop()

  // The same song with the solo shortened to ten seconds.
  const short = engineOn([
    "[00:40.00] First line after the intro",
    "[00:44.00] Second line",
    "[00:58.00] After the solo",
    "[01:02.00] The last line"
  ].join("\n"))

  assert.deepEqual(at(short, 0.5), [ 36 ], "the intro is still long enough to cut")
  assert.deepEqual(at(short, 50), [ 36 ], "but a ten-second solo is not — no second seek")
  short.engine.stop()
})

test("a line still being sung is never cut short", () => {
  const setup = engineOn()

  // Inside the first line, which runs from 40s. The 28-second solo is coming,
  // but the singer is mid-phrase.
  assert.deepEqual(at(setup, 40.5), [])
  setup.engine.stop()
})

test("a long tail after the last word ends the song instead of playing out", () => {
  const setup = engineOn()

  // The last line starts at 80s and the file runs to 200s. The cut stops a
  // hair short of the end so the source runs out and reports the song over.
  assert.deepEqual(at(setup, 90), [ 199.75 ])
  setup.engine.stop()
})

test("a song that ends soon after its last word plays out", () => {
  const setup = engineOn(LRC, { duration: 90 })

  assert.deepEqual(at(setup, 86), [])
  setup.engine.stop()
})

test("the count-in's pre-roll is never skipped", () => {
  const setup = engineOn()

  // Negative song time: the clock is running ahead of the audio so the
  // count-in has somewhere to happen.
  assert.deepEqual(at(setup, -2), [])
  setup.engine.stop()
})

test("skipping can be turned off", () => {
  const setup = engineOn(LRC, { settings: fakeSettings({ skipLongInstrumentals: false }) })

  assert.deepEqual(at(setup, 0.5), [])
  setup.engine.stop()
})

test("the seek is in the file's clock, not the recording's", () => {
  const setup = engineOn()
  // A YouTube instrumental running 1.5s behind the recording the lyrics were
  // timed to: the words are at 40s, the audio for them at 41.5s.
  setup.engine.setAlignmentOffset(1.5)

  // The transport's clock is 1.5s ahead of the recording's, so this is half a
  // second into a song whose first word lands at 40s on the recording.
  assert.deepEqual(at(setup, 2), [ 37.5 ])
  setup.engine.stop()
})

test("a song with no lyrics at all is left alone", () => {
  const setup = engineOn("")

  assert.deepEqual(at(setup, 30), [])
  setup.engine.stop()
})
