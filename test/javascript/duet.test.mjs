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
  // The real transport moves the play head and tells everyone; the engine
  // skips long instrumental stretches through this (see engine.test.mjs).
  seek(seconds) {
    this.currentTime = Math.min(seconds, this.duration)
    this.dispatchEvent(new CustomEvent("seeked", { detail: { time: this.currentTime } }))
  }
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

// --- Finding a split in songs that don't spell one out ---------------------
//
// Marked duets are rare; two people on one microphone are not. Everything
// below is about the three ways a split is found short of "v1:"/"v2:", and
// about the false positive each of them has to avoid.

test("names in the lyrics are numbered by where they first appear", () => {
  const lines = LyricsTimeline.parse([
    "[00:00.00] Rihanna: the first line",
    "[00:02.00] Eminem: the answer",
    "[00:04.00] Rihanna: back to me",
    "[00:06.00] Eminem: and back again",
    "[00:08.00] Both: together now"
  ].join("\n")).lines

  assert.deepEqual(lines.map((line) => line.singer), [ 1, 2, 1, 2, null ])
  assert.equal(lines[0].text, "the first line", "the name is not sung, so it is not shown")
  assert.equal(lines[4].text, "together now")
})

test("a bracketed name works the same way", () => {
  const lines = LyricsTimeline.parse([
    "[00:00.00] [Elton] I hope you don't mind",
    "[00:02.00] [Kiki] that I put down in words",
    "[00:04.00] [Elton] how wonderful life is",
    "[00:06.00] [Kiki] while you're in the world"
  ].join("\n")).lines

  assert.deepEqual(lines.map((line) => line.singer), [ 1, 2, 1, 2 ])
  assert.equal(lines[0].text, "I hope you don't mind")
})

test("a section header hands its lines to whoever it names", () => {
  const lines = LyricsTimeline.parse([
    "[00:00.00] [Verse 1: Beyonce]",
    "[00:02.00] my first line",
    "[00:04.00] my second line",
    "[00:06.00] [Verse 2: Jay]",
    "[00:08.00] his first line",
    "[00:10.00] his second line"
  ].join("\n")).lines

  assert.deepEqual(lines.map((line) => line.singer), [ null, 1, 1, null, 2, 2 ])
})

test("a lyric that merely contains a colon is not a duet marker", () => {
  const lines = LyricsTimeline.parse([
    "[00:00.00] Baby: hold on tight",
    "[00:02.00] the road is long",
    "[00:04.00] and we are young"
  ].join("\n")).lines

  assert.deepEqual(lines.map((line) => line.singer), [ null, null, null ])
  assert.equal(lines[0].text, "Baby: hold on tight", "nothing was stripped out of the line")
})

// Lyrics that only bracket the guest's lines are describing a duet just as
// plainly as ones that mark both sides.
test("one marked part hands every unmarked line to the other singer", () => {
  const lines = LyricsTimeline.parse([
    "[00:00.00] my verse",
    "[00:02.00] still my verse",
    "[00:04.00] f: her chorus",
    "[00:06.00] f: still her chorus",
    "[00:08.00] both: and out together"
  ].join("\n")).lines

  assert.deepEqual(lines.map((line) => line.singer), [ 1, 1, 2, 2, null ])
})

// The last resort: verses alternate, and whatever repeats is the chorus.
// Three-line sections with eight-second breaks between them — a section has to
// be a verse's worth of lines before a gap is read as ending it.
const STRUCTURED_LRC = [
  "[00:00.00] verse one line one",
  "[00:02.00] verse one line two",
  "[00:04.00] verse one line three",
  "[00:12.00] the chorus goes here",
  "[00:14.00] and here as well",
  "[00:16.00] and once more",
  "[00:24.00] verse two line one",
  "[00:26.00] verse two line two",
  "[00:28.00] verse two line three",
  "[00:36.00] the chorus goes here",
  "[00:38.00] and here as well",
  "[00:40.00] and once more",
  "[00:48.00] the bridge is mine",
  "[00:50.00] and mine as well",
  "[00:52.00] and mine again",
  "[01:00.00] your bridge answers",
  "[01:02.00] and answers again",
  "[01:04.00] and answers once more"
].join("\n")

test("a song with no markers at all can still be split by its structure", () => {
  const timeline = LyricsTimeline.parse(STRUCTURED_LRC)

  // Nothing is coloured until somebody asks for the split — a solo singer must
  // not see a song painted in two parts.
  assert.deepEqual(timeline.lines.map((line) => line.singer), new Array(18).fill(null))
  assert.equal(timeline.splittable, true)

  assert.equal(timeline.applySplit(), true)
  assert.deepEqual(timeline.lines.map((line) => line.singer), [
    1, 1, 1, // verse one
    null, null, null, // the chorus repeats, so it is everyone's
    2, 2, 2, // verse two
    null, null, null,
    1, 1, 1, // the bridge goes back round
    2, 2, 2
  ])
})

test("a song too short or too shapeless to divide is left whole", () => {
  const timeline = LyricsTimeline.parse([
    "[00:00.00] one line",
    "[00:02.00] and another",
    "[00:04.00] and a third",
    "[00:06.00] and a fourth"
  ].join("\n"))


  assert.equal(timeline.splittable, false)
  assert.equal(timeline.applySplit(), false)
  assert.deepEqual(timeline.lines.map((line) => line.singer), [ null, null, null, null ])
})

test("a marked duet is reported splittable without being restructured", () => {
  const timeline = LyricsTimeline.parse(DUET_LRC)

  assert.equal(timeline.splittable, true)
  assert.equal(timeline.applySplit(), true)
  assert.deepEqual(timeline.lines.map((line) => line.singer), [ 1, 2, 1, null ], "the markers still decide")
})

test("section labels are not two singers", () => {
  const timeline = LyricsTimeline.parse([
    "[00:00.00] [Verse 1] the opening line",
    "[00:02.00] [Verse 1] and the next",
    "[00:04.00] [Chorus] the chorus goes here",
    "[00:06.00] [Chorus] and here as well",
    "[00:08.00] [Verse 2] the second verse",
    "[00:10.00] [Chorus] the chorus goes here"
  ].join("\n"))

  assert.deepEqual(timeline.lines.map((line) => line.singer), new Array(6).fill(null))
  assert.equal(timeline.lines[0].text, "[Verse 1] the opening line", "a label is left where it was")
})

test("a bracketed part marker without a colon still counts", () => {
  const lines = LyricsTimeline.parse([
    "[00:00.00] [V1] my line",
    "[00:02.00] [V2] your line",
    "[00:04.00] [Both] and ours"
  ].join("\n")).lines

  assert.deepEqual(lines.map((line) => line.singer), [ 1, 2, null ])
  assert.deepEqual(lines.map((line) => line.text), [ "my line", "your line", "and ours" ])
})

// A slow song leaves seconds between two lines of the same breath, and line
// ends are mostly estimates. Without folding the short groups together, every
// line of a ballad becomes its own section and the two singers end up trading
// the microphone line by line.
test("pauses inside a verse do not become section boundaries", () => {
  const ballad = []
  for (let index = 0; index < 16; index++) {
    const seconds = index * 6 // six seconds apart, all of it one long verse
    ballad.push(`[00:${String(seconds).padStart(2, "0")}.00] slow line number ${index}`)
  }

  const timeline = LyricsTimeline.parse(ballad.join("\n"))
  timeline.applySplit()

  // Whatever it decides, it must not hand every other line to the other
  // singer: a real section is at least a few lines long.
  const runs = timeline.lines.reduce((lengths, line, index) => {
    if (index > 0 && line.singer === timeline.lines[index - 1].singer) lengths[lengths.length - 1] += 1
    else lengths.push(1)
    return lengths
  }, [])

  assert.ok(Math.min(...runs) >= 3, `each singer keeps the line for a while, got runs ${runs}`)
})

// Some duets trade a line each the whole way through and say nothing about it
// in their lyrics. Structure groups by the breaks between lines, so it hands
// out whole verses — right for most duets, wrong for these.
test("a named call-and-response duet alternates every line", () => {
  const timeline = LyricsTimeline.parse(STRUCTURED_LRC)
  const track = { title: "Don't Go Breaking My Heart (Remastered)", artist: "Elton John" }

  assert.equal(timeline.splittableFor(track), true)
  assert.equal(timeline.applySplit(track), true)

  const parts = timeline.lines.map((line) => line.singer)
  assert.deepEqual(parts, parts.map((_part, index) => (index % 2) + 1))
})

test("the same lyrics under any other name still split by structure", () => {
  const timeline = LyricsTimeline.parse(STRUCTURED_LRC)
  timeline.applySplit({ title: "Some Other Song", artist: "Somebody Else" })

  // Structural blocks, not strict alternation.
  assert.deepEqual(timeline.lines.map((line) => line.singer).slice(0, 6), [ 1, 1, 1, null, null, null ])
})

test("a marked duet ignores the call-and-response list", () => {
  const timeline = LyricsTimeline.parse(DUET_LRC)
  timeline.applySplit({ title: "Don't Go Breaking My Heart", artist: "Elton John" })

  assert.deepEqual(timeline.lines.map((line) => line.singer), [ 1, 2, 1, null ], "the markers still decide")
})
