// Karaoke playback: the instrumental and the isolated vocal stem, mixed under
// one fader, on the shared AudioContext.
//
// Both tracks are fetched and decoded up front and played as AudioBufferSource
// nodes started at the same context time, which makes them sample-locked by
// construction. Two <audio> elements would drift by tens of milliseconds over
// a song and desync again after every seek, and correcting that means nudging
// playbackRate, which is audible on music.
//
// The cost is memory (a four-minute stereo track decodes to roughly 90MB) and
// a couple of seconds of decoding before the first note — which is why loading
// starts as soon as the song is ready, while the singer is still on the setup
// screen. Buffers are released on destroy().
//
// This is also the stage's clock: currentTime comes from the context, not from
// a media element, so mic frames timestamped on the audio thread can be mapped
// onto song time exactly (see songTimeAt).

// Sources are scheduled a render quantum or two into the future so both start
// on the same one, rather than whenever each call happens to land.
const SCHEDULE_AHEAD_SECONDS = 0.03

export class Transport extends EventTarget {
  constructor(context) {
    super()
    this.context = context
    this.buffers = { instrumental: null, vocals: null }
    this.sources = { instrumental: null, vocals: null }

    this.masterGain = context.createGain()
    this.masterGain.connect(context.destination)

    this.instrumentalGain = context.createGain()
    this.instrumentalGain.connect(this.masterGain)

    this.vocalsGain = context.createGain()
    this.vocalsGain.gain.value = 0
    this.vocalsGain.connect(this.masterGain)

    this.playing = false
    this.pausedOffset = 0
    this.startCtxTime = 0
    this.startOffset = 0
    this.epoch = 0
    this.stopping = false
  }

  // Where the guide melody and anything else generated should be routed.
  get output() {
    return this.masterGain
  }

  get duration() {
    return this.buffers.instrumental?.duration || 0
  }

  get hasVocals() {
    return Boolean(this.buffers.vocals)
  }

  // Negative while a count-in is running: the clock starts before the audio.
  get currentTime() {
    const time = this.playing
      ? this.startOffset + (this.context.currentTime - this.startCtxTime)
      : this.pausedOffset
    return Math.min(time, this.duration)
  }

  // Maps a context timestamp (from a mic worklet frame) onto song time, or
  // null when the frame predates the current playback epoch — which is what
  // stops frames captured before a seek from being scored against what plays
  // after it.
  songTimeAt(contextTime) {
    if (!this.playing || contextTime < this.startCtxTime) return null

    return this.startOffset + (contextTime - this.startCtxTime)
  }

  // The inverse of songTimeAt: when a given moment of the song will be heard.
  // Used to schedule generated audio (the guide melody) against playback.
  contextTimeFor(songTime) {
    if (!this.playing) return null

    return this.startCtxTime + (songTime - this.startOffset)
  }

  async load({ instrumentalUrl, vocalsUrl }) {
    let loaded = 0
    let total = 0
    const onBytes = (bytes, contentLength) => {
      loaded += bytes
      total += contentLength
      this.dispatchEvent(new CustomEvent("progress", { detail: { loaded, total } }))
    }

    try {
      // The vocal stem is optional — songs upgraded from an older cache have
      // none — so a failure there costs the fader, not the song.
      const [ instrumental, vocals ] = await Promise.all([
        this.#fetchAndDecode(instrumentalUrl, onBytes),
        vocalsUrl ? this.#fetchAndDecode(vocalsUrl, onBytes).catch(() => null) : Promise.resolve(null)
      ])

      this.buffers = { instrumental, vocals }
      this.dispatchEvent(new CustomEvent("loaded", { detail: { hasVocals: Boolean(vocals) } }))
      return true
    } catch (error) {
      this.dispatchEvent(new CustomEvent("loaderror", { detail: { error } }))
      return false
    }
  }

  async #fetchAndDecode(url, onBytes) {
    const response = await fetch(url)
    if (!response.ok) throw new Error(`${url} responded ${response.status}`)

    const contentLength = Number(response.headers.get("content-length")) || 0
    let bytes

    if (response.body) {
      const reader = response.body.getReader()
      const chunks = []
      let received = 0

      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        chunks.push(value)
        received += value.length
        // contentLength is reported once, on the first chunk, so the running
        // total isn't multiplied by the number of chunks.
        onBytes(value.length, chunks.length === 1 ? contentLength : 0)
      }

      bytes = new Uint8Array(received)
      let offset = 0
      for (const chunk of chunks) {
        bytes.set(chunk, offset)
        offset += chunk.length
      }
      bytes = bytes.buffer
    } else {
      bytes = await response.arrayBuffer()
      onBytes(bytes.byteLength, contentLength || bytes.byteLength)
    }

    return this.context.decodeAudioData(bytes)
  }

  // preRollSeconds runs the clock ahead of the audio, so a count-in can play
  // over silence and the song starts exactly as it finishes.
  play({ preRollSeconds = 0 } = {}) {
    if (this.playing || !this.buffers.instrumental) return

    const beginAt = Math.min(this.pausedOffset, this.duration)
    const startAt = this.context.currentTime + SCHEDULE_AHEAD_SECONDS

    this.epoch += 1
    this.startCtxTime = startAt
    this.startOffset = beginAt - preRollSeconds
    this.playing = true

    this.#startSources(startAt + preRollSeconds, beginAt)
    this.dispatchEvent(new CustomEvent("play"))
  }

  pause() {
    if (!this.playing) return

    this.pausedOffset = Math.max(0, this.currentTime)
    this.playing = false
    this.#stopSources()
    this.dispatchEvent(new CustomEvent("pause"))
  }

  seek(seconds) {
    const target = Math.max(0, Math.min(seconds, this.duration))

    if (!this.playing) {
      this.pausedOffset = target
      this.dispatchEvent(new CustomEvent("seeked", { detail: { time: target } }))
      return
    }

    this.#stopSources()

    const startAt = this.context.currentTime + SCHEDULE_AHEAD_SECONDS
    this.epoch += 1
    this.startCtxTime = startAt
    this.startOffset = target
    this.pausedOffset = target

    this.#startSources(startAt, target)
    this.dispatchEvent(new CustomEvent("seeked", { detail: { time: target } }))
  }

  // 0..1 of the original vocal, ramped rather than stepped so the fader
  // doesn't click.
  setVocalGain(fraction, rampMs = 60) {
    const value = Math.max(0, Math.min(1, fraction))
    const gain = this.vocalsGain.gain
    gain.cancelScheduledValues(this.context.currentTime)
    gain.setValueAtTime(gain.value, this.context.currentTime)
    gain.linearRampToValueAtTime(value, this.context.currentTime + rampMs / 1000)
  }

  destroy() {
    this.#stopSources()
    this.playing = false
    this.buffers = { instrumental: null, vocals: null }
    this.instrumentalGain.disconnect()
    this.vocalsGain.disconnect()
    this.masterGain.disconnect()
  }

  #startSources(when, offset) {
    this.sources.instrumental = this.#createSource(this.buffers.instrumental, this.instrumentalGain)
    this.sources.vocals = this.#createSource(this.buffers.vocals, this.vocalsGain)

    // The instrumental defines the end of the song; the stem may be a hair
    // shorter or longer after encoding.
    if (this.sources.instrumental) {
      this.sources.instrumental.onended = () => {
        if (this.stopping || !this.playing) return

        this.playing = false
        this.pausedOffset = this.duration
        this.dispatchEvent(new CustomEvent("ended"))
      }
    }

    for (const source of [ this.sources.instrumental, this.sources.vocals ]) {
      source?.start(when, Math.min(offset, source.buffer.duration))
    }
  }

  #createSource(buffer, destination) {
    if (!buffer) return null

    const source = this.context.createBufferSource()
    source.buffer = buffer
    source.connect(destination)
    return source
  }

  // Stopping a source fires its onended; the flag keeps that from being
  // mistaken for the song finishing.
  #stopSources() {
    this.stopping = true
    for (const key of [ "instrumental", "vocals" ]) {
      const source = this.sources[key]
      if (!source) continue

      source.onended = null
      try {
        source.stop()
      } catch {
        // Already stopped, or never started.
      }
      source.disconnect()
      this.sources[key] = null
    }
    this.stopping = false
  }
}
