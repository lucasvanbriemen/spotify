// Runs on the audio-rendering thread (loaded via audioWorklet.addModule, not
// the importmap): accumulates mic samples into ~40ms analysis windows and
// posts a detected pitch back to the main thread. Normalized autocorrelation
// with parabolic interpolation — a standard monophonic pitch-tracking
// technique (the same kind an instrument tuner uses), well suited to a
// single singer's voice.
const BUFFER_SIZE = 2048
// A singing voice rarely leaves roughly E2–C6; searching outside that range
// only invites octave errors from noise.
const MIN_HZ = 70
const MAX_HZ = 1000
// Below this normalized correlation there's no clear periodicity — treat it
// as unvoiced/noise rather than guess.
const VOICED_CORRELATION_THRESHOLD = 0.35
const SILENCE_RMS_THRESHOLD = 0.01

class KaraokePitchProcessor extends AudioWorkletProcessor {
  constructor() {
    super()
    this.buffer = new Float32Array(BUFFER_SIZE)
    this.writeIndex = 0
  }

  process(inputs) {
    const channel = inputs[0]?.[0]
    if (!channel) return true

    for (let i = 0; i < channel.length; i++) {
      this.buffer[this.writeIndex++] = channel[i]
      if (this.writeIndex === BUFFER_SIZE) {
        this.port.postMessage(this.analyze())
        this.writeIndex = 0
      }
    }
    return true
  }

  analyze() {
    let energy = 0
    for (let i = 0; i < BUFFER_SIZE; i++) energy += this.buffer[i] * this.buffer[i]
    const rms = Math.sqrt(energy / BUFFER_SIZE)
    if (rms < SILENCE_RMS_THRESHOLD) return { hz: null, rms }

    return { hz: this.detectPitch(energy), rms }
  }

  detectPitch(energy) {
    const minLag = Math.floor(sampleRate / MAX_HZ)
    const maxLag = Math.min(Math.floor(sampleRate / MIN_HZ), BUFFER_SIZE - 1)

    let bestLag = -1
    let bestCorrelation = 0

    for (let lag = minLag; lag <= maxLag; lag++) {
      let correlation = 0
      for (let i = 0; i < BUFFER_SIZE - lag; i++) correlation += this.buffer[i] * this.buffer[i + lag]
      if (correlation > bestCorrelation) {
        bestCorrelation = correlation
        bestLag = lag
      }
    }

    if (bestLag <= 0 || energy === 0 || bestCorrelation / energy < VOICED_CORRELATION_THRESHOLD) return null

    const refinedLag = bestLag + this.parabolicShift(bestLag, minLag, maxLag, bestCorrelation)
    return refinedLag > 0 ? sampleRate / refinedLag : null
  }

  // Fits a parabola through the best lag and its neighbors for sub-sample
  // precision — needed for cents-level accuracy, since a whole-sample lag
  // step near 200Hz is already several cents wide.
  parabolicShift(bestLag, minLag, maxLag, centerCorrelation) {
    const correlationAt = (lag) => {
      let sum = 0
      for (let i = 0; i < BUFFER_SIZE - lag; i++) sum += this.buffer[i] * this.buffer[i + lag]
      return sum
    }

    const before = correlationAt(Math.max(bestLag - 1, minLag))
    const after = correlationAt(Math.min(bestLag + 1, maxLag))
    const denominator = 2 * (2 * centerCorrelation - before - after)
    return denominator !== 0 ? (before - after) / denominator : 0
  }
}

registerProcessor("karaoke-pitch-processor", KaraokePitchProcessor)
