// Unit tests for the lyrics timeline, run with `node --test test/javascript`.
//
// The node_modules/karaoke shim in this directory maps the importmap's bare
// "karaoke/*" specifiers onto app/javascript/karaoke/*.js, so the modules run
// here exactly as written.
import { test } from "node:test"
import assert from "node:assert/strict"

import { LyricsTimeline } from "karaoke/lyrics_timing"

const LRC = [
  "[00:10.00] First line here",
  "[00:14.00] Second line",
  "[00:18.00] Third line words"
].join("\n")

function payloadLine(start, end, words) {
  return { start, end, words }
}

test("payload words merge by start time, so a server-skipped line desyncs nothing after it", () => {
  // The server skipped the second line (zero-width window); an index-based
  // pairing would give the third line no words at all.
  const payload = {
    lines: [
      payloadLine(10.0, 13.5, [
        { w: "First", start: 10, end: 11 }, { w: "line", start: 11, end: 12 }, { w: "here", start: 12, end: 13.5 }
      ]),
      payloadLine(18.0, 21.0, [
        { w: "Third", start: 18, end: 19 }, { w: "line", start: 19, end: 20 }, { w: "words", start: 20, end: 21 }
      ])
    ]
  }

  const timeline = LyricsTimeline.parse(LRC, payload)
  assert.equal(timeline.length, 3)

  // Line 1 took its payload words.
  assert.equal(timeline.lines[0].words[0].text, "First")
  assert.equal(timeline.lines[0].endTime, 13.5)

  // Line 2 fell back to estimates (no matching payload start).
  assert.equal(timeline.lines[1].words.length, 2)

  // Line 3 still found ITS payload line — the whole point of the fix.
  assert.equal(timeline.lines[2].words[0].start, 18)
  assert.equal(timeline.lines[2].endTime, 21)
})

test("a payload line is claimed at most once when LRC compression repeats a timestamp", () => {
  const lrc = "[00:10.00][00:10.00] Repeated words"
  const payload = {
    lines: [ payloadLine(10.0, 12.0, [ { w: "Repeated", start: 10, end: 11 }, { w: "words", start: 11, end: 12 } ]) ]
  }

  const timeline = LyricsTimeline.parse(lrc, payload)
  assert.equal(timeline.length, 2)
  assert.equal(timeline.lines[0].endTime, 12) // claimed the payload
  assert.notEqual(timeline.lines[1].endTime, 12) // estimated, not double-claimed
})

test("a duet marker in the payload words is dropped to match the displayed text", () => {
  const lrc = "[00:10.00] v1: Hello world"
  const payload = {
    lines: [
      payloadLine(10.0, 12.0, [
        { w: "v1:", start: 10, end: 10.2 }, { w: "Hello", start: 10.2, end: 11 }, { w: "world", start: 11, end: 12 }
      ])
    ]
  }

  const timeline = LyricsTimeline.parse(lrc, payload)
  const line = timeline.lines[0]

  assert.equal(line.text, "Hello world")
  assert.equal(line.singer, 1)
  assert.equal(line.words[0].text, "Hello")
  // Sweep is characters-sung over the DISPLAYED text: "Hello world" = 11.
  assert.equal(line.charTotal, 11)
})

test("without a payload, words are estimated and every line still renders", () => {
  const timeline = LyricsTimeline.parse(LRC, null)
  assert.equal(timeline.length, 3)
  for (const line of timeline.lines) {
    assert.ok(line.words.length > 0)
    assert.ok(line.endTime > line.time)
  }
})

test("stateAt sweeps forward through a line", () => {
  const timeline = LyricsTimeline.parse(LRC, null)

  assert.equal(timeline.stateAt(5).index, -1)
  const early = timeline.stateAt(10.1)
  const late = timeline.stateAt(11.2)
  assert.equal(early.index, 0)
  assert.equal(late.index, 0)
  assert.ok(late.sweep >= early.sweep)
  assert.equal(timeline.stateAt(15).index, 1)
})
