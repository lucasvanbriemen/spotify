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
  // Full by default. This used to be off, on the reasoning that the original
  // singer coming through unasked is a surprise — but the fader that let you
  // raise it lived on the stage control bar, and that bar is one knob now, so
  // "off by default" had become "off, with nothing anywhere to turn it up".
  // Lower it from the setup screen on a song you know well.
  vocalGuidePercent: 100,
  guideMelody: false,
  // Chrome's echo cancellation treats page audio as the far end and will
  // genuinely suppress instrumental bleed — at the cost of mangling sung
  // pitch. Off by default; worth it only for a mic far from the singer.
  reduceMusicPickup: false,
  // How loud the singers hear themselves over the music (see mic_monitor.js).
  // Off by default, and deliberately: with echo cancellation off, a monitor
  // raised into open speakers is a feedback loop, so it has to be a thing
  // somebody asked for on a setup that can take it — headphones, or a speaker
  // pointed away from the mic.
  micMonitorPercent: 0,
  // Where a karaoke PA sits: enough to stop a bare voice sounding thin over a
  // full mix, not enough to hide the words.
  micMonitorReverbPercent: 25,
  // Offer to jump the long stretches with nothing to sing — a two-minute
  // outro, an eight-bar solo. The offer is a button on the stage and nothing
  // moves until it is pressed; this only controls whether it appears at all.
  // The engine's INSTRUMENTAL_SKIP_SECONDS is the threshold.
  skipLongInstrumentals: true,
  singers: null,
  // Where the screen was when it was last reloaded — see the coordinator's
  // rememberSession.
  session: null
}

function read(key) {
  try {
    const raw = localStorage.getItem(PREFIX + key)
    return raw === null ? undefined : JSON.parse(raw)
  } catch {
    return undefined // unparseable or storage blocked — fall back to the default
  }
}

function remove(key) {
  try {
    localStorage.removeItem(PREFIX + key)
  } catch {
    // Storage blocked: there was nothing persisted to clear anyway.
  }
}

function write(key, value) {
  try {
    localStorage.setItem(PREFIX + key, JSON.stringify(value))
  } catch {
    // Private browsing or a full quota: preferences just don't persist.
  }
}

// One-time cleanup, not a general migration framework. A browser that used the
// old stage fader has a vocalGuidePercent of its own in localStorage, and a
// stored value always beats the default — so raising the default above would
// have left exactly the returning singers it was meant for still silent, with
// the control now on a screen they had already walked past. Dropping the
// stored key hands them the new default once; anything they set afterwards on
// the setup screen persists normally.
const GUIDE_DEFAULT_MIGRATION = "vocalGuideDefaultedToFull"

if (!read(GUIDE_DEFAULT_MIGRATION)) {
  remove("vocalGuidePercent")
  write(GUIDE_DEFAULT_MIGRATION, true)
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

  // How far behind the scheduling clock the sound actually is. Lines the
  // visuals up with what reaches the room. outputLatency covers the browser
  // and the OS but not the TV, which is what the trim is for.
  displayOffsetSeconds(context) {
    const output = context?.outputLatency || context?.baseLatency || 0.02
    return output + this.get("latencyTrimMs") / 1000
  },

  // The same delay, plus how long the singer's voice takes to come back in
  // through the mic. Subtracted from a frame's timestamp before scoring it.
  scoringOffsetSeconds(context) {
    const output = context?.outputLatency || context?.baseLatency || 0.02
    return output + CAPTURE_LATENCY_SECONDS + this.get("latencyTrimMs") / 1000
  }
}

// A typical USB or built-in mic, measured to the analysis window's centre.
// Only the residual after this matters, and the trim absorbs that.
const CAPTURE_LATENCY_SECONDS = 0.03
