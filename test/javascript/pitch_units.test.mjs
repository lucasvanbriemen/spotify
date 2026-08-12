// Register handling: octave-folded scoring, the lane fold's clamp, and the
// melody's register midpoint. Run with `node --test test/javascript`.
import { test } from "node:test"
import assert from "node:assert/strict"

import { creditFor } from "karaoke/scoring"
import { PitchLane } from "karaoke/pitch_lane"
import { Melody } from "karaoke/melody"
import { LyricsTimeline } from "karaoke/lyrics_timing"

test("scoring is octave-invariant: the same note any octave down earns full credit", () => {
  const target = 69 // A4 = 440Hz

  assert.equal(creditFor(440, target), 1)
  assert.equal(creditFor(220, target), 1) // one octave down
  assert.equal(creditFor(110, target), 1) // two octaves down
  assert.equal(creditFor(880, target), 1) // one octave up

  // A full semitone off is partial credit in every octave alike.
  const near = creditFor(466.16, target)
  const nearLow = creditFor(233.08, target)
  assert.ok(near > 0 && near < 1)
  assert.ok(Math.abs(near - nearLow) < 0.01)
})

// foldToLane runs on a plain object: it only reads this.melody.
function fold(midiMin, midiMax, midi, previous = null) {
  return PitchLane.prototype.foldToLane.call({ melody: { midiMin, midiMax } }, midi, previous)
}

test("a voice a lane narrower than an octave can't reach is pinned to the lane edge, not drawn off-canvas", () => {
  // Lane spans 8 semitones: some registers have no whole-octave shift into it.
  assert.equal(fold(60, 68, 45), 60) // deep voice -> pinned to the bottom
  assert.equal(fold(60, 68, 81), 68) // high voice -> pinned to the top

  // Reachable registers still fold normally.
  assert.equal(fold(60, 68, 50), 62)
  assert.equal(fold(60, 72, 52), 64)
})

test("the melody knows its register midpoint", () => {
  const timeline = LyricsTimeline.parse("[00:01.00] La la la")
  const melody = Melody.parse(
    { notes: [ { start: 1, end: 2, midi: 60 }, { start: 2, end: 3, midi: 64 }, { start: 3, end: 4, midi: 67 } ] },
    timeline
  )

  assert.equal(melody.medianMidi, 64)
  assert.equal(Melody.empty().medianMidi, null)
})
