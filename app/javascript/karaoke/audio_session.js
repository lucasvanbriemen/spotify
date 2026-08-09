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

  // "playback" trades a little latency for buffer headroom: we care that the
  // audio never glitches, not that a keypress responds instantly.
  const context = new AudioContext({ latencyHint: "playback" })
  await context.audioWorklet.addModule(workletUrl)

  session = {
    context,

    // Browsers start a context suspended until a user gesture. Call this from
    // inside a click handler before expecting sound.
    async ensureRunning() {
      if (context.state === "suspended") await context.resume().catch(() => {})
      return context.state === "running"
    },

    async close() {
      session = null
      await context.close().catch(() => {})
    }
  }

  await session.ensureRunning()
  return session
}

export function currentAudioSession() {
  return session
}
