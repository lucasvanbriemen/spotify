// The "guide melody" every karaoke machine has: a quiet tone that plays the
// line you're supposed to be singing. Invaluable on a song you half-know.
//
// One oscillator for the whole song, re-tuned and gated per note by the audio
// clock rather than by timers, so it stays in step with playback through
// pauses and seeks.

// Triangle has enough overtones to place the pitch without the harshness of a
// saw, and sits under the music instead of on top of it.
const WAVEFORM = "triangle"
const LEVEL = 0.15
// How far ahead notes are scheduled, topped up every frame.
const LOOKAHEAD_SECONDS = 5
// Short ramps so each note is clearly separate but nothing clicks.
const GATE_SECONDS = 0.005

export class GuideMelody {
  constructor(context, destination) {
    this.context = context
    this.melody = null
    this.enabled = false
    this.scheduledUpTo = -1
    // Whole octaves (in semitones), so a deep or high voice hears the guide
    // in its own register. Scoring is octave-invariant, so this is display-
    // level only — see KaraokeEngine#guideTranspose.
    this.transpose = 0

    this.gate = context.createGain()
    this.gate.gain.value = 0

    this.level = context.createGain()
    this.level.gain.value = 0
    this.gate.connect(this.level)
    this.level.connect(destination)

    this.oscillator = context.createOscillator()
    this.oscillator.type = WAVEFORM
    this.oscillator.connect(this.gate)
    this.oscillator.start()
  }

  setMelody(melody) {
    this.melody = melody && !melody.isEmpty ? melody : null
    this.reset()
  }

  setTranspose(semitones) {
    if (semitones === this.transpose) return

    this.transpose = semitones
    this.reset() // anything already scheduled is at the old pitch
  }

  setEnabled(enabled) {
    this.enabled = enabled
    const now = this.context.currentTime
    this.level.gain.cancelScheduledValues(now)
    this.level.gain.setValueAtTime(this.level.gain.value, now)
    this.level.gain.linearRampToValueAtTime(enabled ? LEVEL : 0, now + 0.08)
    if (!enabled) this.reset()
  }

  // Called after any seek or pause: everything already scheduled describes a
  // moment in the song that is no longer about to happen.
  reset() {
    const now = this.context.currentTime
    this.oscillator.frequency.cancelScheduledValues(now)
    this.gate.gain.cancelScheduledValues(now)
    this.gate.gain.setValueAtTime(0, now)
    this.scheduledUpTo = -1
  }

  // Driven from the engine's frame loop. songToContext converts a song time to
  // the context time it will be heard at.
  schedule(songTime, songToContext) {
    if (!this.enabled || !this.melody) return

    const until = songTime + LOOKAHEAD_SECONDS
    const from = Math.max(songTime, this.scheduledUpTo)
    if (until <= from) return

    for (const note of this.melody.notesInWindow(from, until)) {
      if (note.start < from) continue

      const startAt = songToContext(note.start)
      const endAt = songToContext(note.end)
      if (startAt === null || endAt === null || startAt < this.context.currentTime) continue

      this.oscillator.frequency.setValueAtTime(440 * 2 ** ((note.midi + this.transpose - 69) / 12), startAt)
      this.gate.gain.setTargetAtTime(1, startAt, GATE_SECONDS)
      this.gate.gain.setTargetAtTime(0, Math.max(startAt + 0.01, endAt - 0.01), GATE_SECONDS)
    }

    this.scheduledUpTo = until
  }

  destroy() {
    try {
      this.oscillator.stop()
    } catch {
      // Already stopped.
    }
    this.oscillator.disconnect()
    this.gate.disconnect()
    this.level.disconnect()
  }
}
