import { MicMonitor } from "karaoke/mic_monitor"

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

  // One monitor bus for every mic on this context, for the same reason the
  // context itself is shared: the singers hear one blend, not one each. Silent
  // and off the destination until someone asks to hear themselves.
  const monitor = new MicMonitor(context)

  session = {
    context,
    monitor,

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
