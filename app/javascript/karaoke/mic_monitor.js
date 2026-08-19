// The singers' own voices, back out of the speakers over the music — what the
// PA in a karaoke box does. Without it you are pitching against the inside of
// your own head while a backing track plays; with it you hear the same blend
// the room does.
//
// Both mics feed one bus, the way they would feed one mixer: the level and the
// reverb belong to the room, not to a singer.
//
//   mic source ─┬──────────────────────────► dry ─┬─► limiter ─► output ─► out
//               └─► pre-delay ─► convolver ─► wet ─┘
//
// FEEDBACK is the risk that shapes all of this. The capture path deliberately
// runs with echo cancellation off, because it moves the detected pitch of a
// sung note (see mic.js) — so a mic hearing its own monitor through open
// speakers is a loop with nothing damping it. Hence: the level starts at zero
// and has to be asked for, the ceiling sits not far above unity, and the
// limiter is not a matter of taste. It turns a runaway into a loud but bounded
// howl someone can reach the slider through, instead of a spike.
//
// The monitor is deliberately NOT in the pitch worklet's path. Scoring has to
// hear the singer, not the singer plus a reverb tail.
import { settings } from "karaoke/settings"

// What 100% means. A monitor wants a little more than unity to sit over a
// backing track, but every dB above it buys feedback.
const MAX_GAIN = 1.5
// A send, so the dry voice stays at unity however wet it gets — but a fully
// wet monitor is a swimming pool, not a stage.
const MAX_WET = 0.8
const REVERB_SECONDS = 1.8
// Long enough to keep the tail off the front of a word (which is what makes a
// cheap reverb sound like a bathroom), short enough not to read as an echo.
const PREDELAY_SECONDS = 0.02
const RAMP_SECONDS = 0.06

export class MicMonitor {
  constructor(context) {
    this.context = context
    this.connected = false
    this.disconnectTimer = null

    // Where the mics arrive.
    this.input = context.createGain()

    this.dry = context.createGain()
    this.wet = context.createGain()
    this.wet.gain.value = 0

    this.predelay = context.createDelay(0.2)
    this.predelay.delayTime.value = PREDELAY_SECONDS

    this.convolver = context.createConvolver()
    this.convolver.buffer = impulseResponse(context, REVERB_SECONDS)

    this.limiter = context.createDynamicsCompressor()
    this.limiter.threshold.value = -6
    this.limiter.knee.value = 6
    this.limiter.ratio.value = 12
    this.limiter.attack.value = 0.003
    this.limiter.release.value = 0.25

    this.output = context.createGain()
    this.output.gain.value = 0

    this.input.connect(this.dry)
    this.input.connect(this.predelay)
    this.predelay.connect(this.convolver)
    this.convolver.connect(this.wet)
    this.dry.connect(this.limiter)
    this.wet.connect(this.limiter)
    this.limiter.connect(this.output)

    this.level = 0
    this.reverb = 0
    this.applySettings()
  }

  // Takes a mic's raw source node, straight off the capture device.
  addSource(node) {
    node.connect(this.input)
  }

  // Called when the setup screen reopens a mic, and on the way into a song, so
  // a level set once holds for the evening.
  applySettings() {
    this.setLevel(settings.get("micMonitorPercent"))
    this.setReverb(settings.get("micMonitorReverbPercent"))
  }

  // 0..100. Zero doesn't merely mute: it takes the bus off the destination, so
  // a page nobody is monitoring on pays nothing for the convolver — Web Audio
  // only pulls what reaches the output.
  setLevel(percent) {
    this.level = clamp(percent)
    const target = (this.level / 100) * MAX_GAIN

    if (target > 0) this.#attach()
    this.#ramp(this.output.gain, target)
    if (target === 0) this.#detachAfterRamp()

    return this.level
  }

  // 0..100 wet.
  setReverb(percent) {
    this.reverb = clamp(percent)
    this.#ramp(this.wet.gain, (this.reverb / 100) * MAX_WET)

    return this.reverb
  }

  destroy() {
    clearTimeout(this.disconnectTimer)
    for (const node of [ this.input, this.dry, this.wet, this.predelay, this.convolver, this.limiter, this.output ]) {
      node.disconnect()
    }
    this.connected = false
  }

  #attach() {
    clearTimeout(this.disconnectTimer)
    this.disconnectTimer = null
    if (this.connected) return

    this.output.connect(this.context.destination)
    this.connected = true
  }

  // After the fade, not during it — cutting the graph on the same tick would
  // chop the voice off mid-word rather than fading it out.
  #detachAfterRamp() {
    if (!this.connected || this.disconnectTimer) return

    this.disconnectTimer = setTimeout(() => {
      this.disconnectTimer = null
      // A level raised again while this was pending must not be torn down.
      if (this.level > 0) return

      this.output.disconnect()
      this.connected = false
    }, RAMP_SECONDS * 1000 + 20)
  }

  // Ramped rather than stepped, or every slider move is a click.
  #ramp(param, value) {
    const now = this.context.currentTime
    param.cancelScheduledValues(now)
    param.setValueAtTime(param.value, now)
    param.linearRampToValueAtTime(value, now + RAMP_SECONDS)
  }
}

function clamp(percent) {
  return Math.max(0, Math.min(100, Number(percent) || 0))
}

// Exponentially decaying noise. Not a real room, but the tail of one, and it
// ships no asset to get there. The exponent is what keeps it from sounding
// like a metal drum: the energy has to leave faster than linearly.
function impulseResponse(context, seconds) {
  const rate = context.sampleRate
  const length = Math.max(1, Math.floor(rate * seconds))
  const buffer = context.createBuffer(2, length, rate)

  for (let channel = 0; channel < buffer.numberOfChannels; channel++) {
    const samples = buffer.getChannelData(channel)
    for (let index = 0; index < length; index++) {
      samples[index] = (Math.random() * 2 - 1) * Math.pow(1 - index / length, 2.5)
    }
  }

  return buffer
}
