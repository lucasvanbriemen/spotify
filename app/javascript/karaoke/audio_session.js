import { MicMonitor } from "karaoke/mic_monitor"
import { settings } from "karaoke/settings"

// The one AudioContext the karaoke stage uses, shared by playback, every mic
// and the guide-melody synth.
//
// Sharing it is the point: context.currentTime then becomes a single clock, so
// a pitch estimate timestamped on the audio thread can be placed on the same
// timeline as the instrumental that provoked it. Separate contexts would each
// run on their own clock and there would be nothing to compare.
//
// Lives for as long as the karaoke page does — songs come and go against it.
let session = null

export async function getAudioSession(workletUrl) {
  if (session) {
    await session.ensureRunning()
    return session
  }

  // "interactive", not "playback". The playback hint buys glitch headroom by
  // making the output buffer as large as it likes — a couple of hundred
  // milliseconds on some machines — and that delay sits between every visual
  // and the sound it belongs to, as well as in the mic round trip. This app
  // has a microphone in the loop and words that must land on the beat, so the
  // low, predictable buffer is worth more than the headroom.
  const context = new AudioContext({ latencyHint: "interactive" })
  await context.audioWorklet.addModule(workletUrl)

  // Everything the room hears passes through this one gain: the music, the
  // guide melody, the singers' own voices. It is the system fader — the thing
  // to reach for when the whole PA is too loud, as opposed to one part of the
  // mix being wrong. Where the OS volume would be, if the browser gave it.
  const master = context.createGain()
  master.gain.value = settings.get("masterPercent") / 100
  master.connect(context.destination)

  // One monitor bus for every mic on this context, for the same reason the
  // context itself is shared: the singers hear one blend, not one each. Silent
  // and off the master until someone asks to hear themselves.
  const monitor = new MicMonitor(context, master)

  session = {
    context,
    monitor,
    master,

    // 0..100. Ramped so a knob click is not a click in the speakers.
    setMasterLevel(percent) {
      const level = Math.max(0, Math.min(100, Math.round(percent)))
      const gain = master.gain
      gain.cancelScheduledValues(context.currentTime)
      gain.setValueAtTime(gain.value, context.currentTime)
      gain.linearRampToValueAtTime(level / 100, context.currentTime + 0.06)
      return level
    },

    // Browsers start a context suspended until a user gesture. Call this from
    // inside a click handler before expecting sound.
    async ensureRunning() {
      if (context.state === "suspended") await context.resume().catch(() => {})
      return context.state === "running"
    },

    async close() {
      session = null
      monitor.destroy()
      await context.close().catch(() => {})
    }
  }

  await session.ensureRunning()
  return session
}

export function currentAudioSession() {
  return session
}
