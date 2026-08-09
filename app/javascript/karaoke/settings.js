// Preferences that should survive a reload: the latency trim, how loud the
// vocal guide is, which mics each singer used. Stored in localStorage under
// one namespaced key per setting so a corrupt value can never take the rest
// down with it.
const PREFIX = "karaoke."

const DEFAULTS = {
  // Added to the measured output latency. TV audio pipelines add 30-150ms the
  // browser cannot see, so this is the knob that actually lines scoring up
  // with what the singer hears.
  latencyTrimMs: 0,
  // Off by default: the original singer coming through unasked is a surprise,
  // and the point of karaoke is that the part is yours. Raise it on a song you
  // only half know.
  vocalGuidePercent: 0,
  guideMelody: false,
  // Chrome's echo cancellation treats page audio as the far end and will
  // genuinely suppress instrumental bleed — at the cost of mangling sung
  // pitch. Off by default; worth it only for a mic far from the singer.
  reduceMusicPickup: false,
  singers: null
}

function read(key) {
  try {
    const raw = localStorage.getItem(PREFIX + key)
    return raw === null ? undefined : JSON.parse(raw)
  } catch {
    return undefined // unparseable or storage blocked — fall back to the default
  }
}

function write(key, value) {
  try {
    localStorage.setItem(PREFIX + key, JSON.stringify(value))
  } catch {
    // Private browsing or a full quota: preferences just don't persist.
  }
}

export const settings = {
  get(key) {
    const stored = read(key)
    return stored === undefined ? DEFAULTS[key] : stored
  },

  set(key, value) {
    write(key, value)
    return value
  },

  // Total seconds to subtract from a mic frame's timestamp before scoring it:
  // how long playback takes to reach the singer's ears, plus how long their
  // voice takes to come back. outputLatency covers the browser and OS but not
  // the TV, which is what the trim is for.
  scoringOffsetSeconds(context) {
    const output = context?.outputLatency || context?.baseLatency || 0.02
    return output + CAPTURE_LATENCY_SECONDS + this.get("latencyTrimMs") / 1000
  }
}

// A typical USB or built-in mic, measured to the analysis window's centre.
// Only the residual after this matters, and the trim absorbs that.
const CAPTURE_LATENCY_SECONDS = 0.03
