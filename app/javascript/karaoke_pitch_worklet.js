// Runs on the audio-rendering thread (loaded via audioWorklet.addModule, not
// the importmap): accumulates mic samples into ~43ms analysis windows and
// posts a detected pitch back to the main thread. Normalized autocorrelation
// with parabolic interpolation — a standard monophonic pitch-tracking
// technique (the same kind an instrument tuner uses), well suited to a
// single singer's voice.
//
// Each estimate carries the context time at the centre of the window it was
// measured from. That timestamp is what lets the engine place a sung note on
// the same timeline as the instrumental, no matter how busy the main thread
// was when the message arrived.
const BUFFER_SIZE = 2048
// Analysing every half-buffer doubles the rate (to ~47Hz at 48kHz) for the
// same window length, which matters for short notes.
const HOP_SIZE = BUFFER_SIZE / 2
// A singing voice rarely leaves roughly E2–C6; searching outside that range
// only invites octave errors from noise.
const MIN_HZ = 70
const MAX_HZ = 1000
// Below this normalized correlation there's no clear periodicity — treat it
// as unvoiced/noise rather than guess. Set high enough that music leaking in
// from the TV usually fails it; a close-miked voice clears it comfortably.
const DEFAULT_CORRELATION_THRESHOLD = 0.5
const DEFAULT_RMS_GATE = 0.01

class KaraokePitchProcessor extends AudioWorkletProcessor {
  constructor() {
    super()
    this.buffer = new Float32Array(BUFFER_SIZE)
    this.writeIndex = 0
    this.filled = 0
    this.correlationThreshold = DEFAULT_CORRELATION_THRESHOLD
    this.rmsGate = DEFAULT_RMS_GATE

    // The setup screen measures how much of the room the mic is picking up and
    // raises the gate accordingly.
    this.port.onmessage = (event) => {
      const { rmsGate, correlationThreshold } = event.data || {}
      if (typeof rmsGate === "number") this.rmsGate = rmsGate
      if (typeof correlationThreshold === "number") this.correlationThreshold = correlationThreshold
    }
  }

  process(inputs) {
    const channel = inputs[0]?.[0]
    if (!channel) return true

    for (let i = 0; i < channel.length; i++) {
      this.buffer[this.writeIndex] = channel[i]
      this.writeIndex = (this.writeIndex + 1) % BUFFER_SIZE
      this.filled++

      if (this.filled >= HOP_SIZE && this.writeIndex % HOP_SIZE === 0) {
        this.filled = 0
        this.port.postMessage(this.analyze())
      }
    }
    return true
  }

  // The ring buffer's oldest sample is wherever the write cursor points, so
  // unwrap it into analysis order before correlating.
  ordered() {
    const window = new Float32Array(BUFFER_SIZE)
    for (let i = 0; i < BUFFER_SIZE; i++) window[i] = this.buffer[(this.writeIndex + i) % BUFFER_SIZE]
    return window
  }

  analyze() {
    const window = this.ordered()

    let energy = 0
    for (let i = 0; i < BUFFER_SIZE; i++) energy += window[i] * window[i]
    const rms = Math.sqrt(energy / BUFFER_SIZE)

    // Timestamped at the middle of the window, which is the moment the
    // estimate actually describes.
    const t = currentTime - BUFFER_SIZE / (2 * sampleRate)

    if (rms < this.rmsGate) return { hz: null, rms, t }

    return { hz: this.detectPitch(window, energy), rms, t }
  }

  detectPitch(window, energy) {
    const minLag = Math.floor(sampleRate / MAX_HZ)
    const maxLag = Math.min(Math.floor(sampleRate / MIN_HZ), BUFFER_SIZE - 1)

    let bestLag = -1
    let bestCorrelation = 0

    for (let lag = minLag; lag <= maxLag; lag++) {
      let correlation = 0
      for (let i = 0; i < BUFFER_SIZE - lag; i++) correlation += window[i] * window[i + lag]
      if (correlation > bestCorrelation) {
        bestCorrelation = correlation
        bestLag = lag
      }
    }

    if (bestLag <= 0 || energy === 0 || bestCorrelation / energy < this.correlationThreshold) return null

    const refinedLag = bestLag + this.parabolicShift(window, bestLag, minLag, maxLag, bestCorrelation)
    return refinedLag > 0 ? sampleRate / refinedLag : null
  }

  // Fits a parabola through the best lag and its neighbors for sub-sample
  // precision — needed for cents-level accuracy, since a whole-sample lag
  // step near 200Hz is already several cents wide.
  parabolicShift(window, bestLag, minLag, maxLag, centerCorrelation) {
    const correlationAt = (lag) => {
      let sum = 0
      for (let i = 0; i < BUFFER_SIZE - lag; i++) sum += window[i] * window[i + lag]
      return sum
    }

    const before = correlationAt(Math.max(bestLag - 1, minLag))
    const after = correlationAt(Math.min(bestLag + 1, maxLag))
    const denominator = 2 * (2 * centerCorrelation - before - after)
    return denominator !== 0 ? (before - after) / denominator : 0
  }
}

registerProcessor("karaoke-pitch-processor", KaraokePitchProcessor)
