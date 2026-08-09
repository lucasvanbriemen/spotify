// Turns the pitch tracker's raw output into something worth drawing.
//
// A frame-by-frame autocorrelation estimate is jumpy in three different ways,
// and each needs a different answer:
//
//   * a few cents of noise on every frame          -> exponential smoothing
//   * occasional single-frame octave errors        -> median filter
//   * brief unvoiced gaps mid-word (consonants)    -> a short hold
//
// Order matters. The median runs first, because averaging an octave error in
// would drag the smoothed value halfway to the wrong octave and take a while
// to crawl back. A median simply discards it.
//
// This is display only. Scoring deliberately uses the raw estimates: smoothing
// trades lag for looks, and scoring already folds octaves and averages across
// a whole note, so it gains nothing and would only respond late.

// ~5 frames at the worklet's ~47Hz is about 100ms — long enough to outvote a
// transient, short enough not to blunt a real note change.
const MEDIAN_WINDOW = 5
// Exponential time constant. Lower is snappier and noisier.
const TIME_CONSTANT_SECONDS = 0.06
// Consonants and breaths drop the voicing for a moment; breaking the line
// there would draw one word as a row of dashes.
const HOLD_SECONDS = 0.12
// A jump this big is a new note, not drift — restart rather than sliding
// across the gap.
const RESET_SEMITONES = 4

export class PitchSmoother {
  constructor() {
    this.reset()
  }

  reset() {
    this.window = []
    this.value = null
    this.lastVoicedAt = null
    this.lastAt = null
  }

  // midi is null when the frame is unvoiced. Returns the value to draw, or
  // null once the singer has genuinely stopped.
  push(midi, at) {
    if (midi === null || !Number.isFinite(midi)) return this.#silence(at)

    this.window.push(midi)
    if (this.window.length > MEDIAN_WINDOW) this.window.shift()

    const median = this.#median()
    const elapsed = this.lastAt === null ? 0 : Math.max(0, at - this.lastAt)
    this.lastAt = at
    this.lastVoicedAt = at

    if (this.value === null || Math.abs(median - this.value) > RESET_SEMITONES) {
      this.value = median
      return this.value
    }

    // Frame-rate independent one-pole: the same responsiveness whether frames
    // arrive every 20ms or every 5.
    const alpha = 1 - Math.exp(-elapsed / TIME_CONSTANT_SECONDS)
    this.value += (median - this.value) * alpha
    return this.value
  }

  #silence(at) {
    this.lastAt = at
    if (this.lastVoicedAt !== null && at - this.lastVoicedAt <= HOLD_SECONDS) {
      return this.value // still inside a consonant; hold the line together
    }

    this.window = []
    this.value = null
    return null
  }

  #median() {
    const sorted = [ ...this.window ].sort((a, b) => a - b)
    return sorted[(sorted.length - 1) >> 1]
  }
}
