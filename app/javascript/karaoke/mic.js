// Microphone capture for one or two singers, each on their own input device,
// both analysed on the shared AudioContext.
//
// Every piece of speech processing is switched off deliberately. Echo
// cancellation and noise suppression are tuned for a talking voice and both
// distort a sung note badly enough to move its detected pitch; automatic gain
// pumps through held notes. The one exception is offered as a setting for
// people whose mic is nowhere near their mouth (see reduceMusicPickup).
const SINGING_CONSTRAINTS = {
  echoCancellation: false,
  noiseSuppression: false,
  autoGainControl: false,
  channelCount: 1
}

// The mics hear the TV as well as the singer. Measuring the room with the
// music playing and gating a few times above that floor is the main defence
// against scoring someone who isn't singing.
const NOISE_FLOOR_MULTIPLIER = 3
const MIN_RMS_GATE = 0.01
// A level meter that followed raw frames would flicker; this is a simple
// one-pole smoother.
const LEVEL_SMOOTHING = 0.3

export class MicSystem {
  constructor(session) {
    this.session = session
    this.granted = false
    this.primeStream = null
  }

  // Device labels stay empty until permission has been given once, so the
  // picker has to ask before it can offer anything meaningful.
  //
  // Asking is expensive on browsers that don't persist the grant (Safari can
  // prompt per getUserMedia call), so this never opens a probe stream it
  // doesn't have to: the Permissions API answers first when it can, and when
  // a probe IS needed it stays alive to become the first singer's input
  // (claimPrimeStream) instead of being stopped and immediately re-requested
  // — one prompt instead of two.
  async requestPermission() {
    if (await this.permissionGranted()) {
      this.granted = true
      return true
    }

    try {
      this.primeStream = await navigator.mediaDevices.getUserMedia({ audio: SINGING_CONSTRAINTS })
      this.granted = true
      return true
    } catch {
      this.granted = false
      return false
    }
  }

  // "granted" without ever prompting; anything else — denied, prompt, or a
  // browser without the API (Firefox has no "microphone" permission name) —
  // reads as "have to ask". Static so the setup screen can check before it
  // has any session to build a MicSystem around.
  static async permissionGranted() {
    try {
      const status = await navigator.permissions.query({ name: "microphone" })
      return status.state === "granted"
    } catch {
      return false
    }
  }

  async permissionGranted() {
    return MicSystem.permissionGranted()
  }

  async listDevices() {
    try {
      const devices = await navigator.mediaDevices.enumerateDevices()
      return devices
        .filter((device) => device.kind === "audioinput")
        .map((device, index) => ({ deviceId: device.deviceId, label: device.label || `Microphone ${index + 1}` }))
    } catch {
      return []
    }
  }

  async createInput(deviceId, { reduceMusicPickup = false } = {}) {
    const input = new MicInput(this.session.context, deviceId, reduceMusicPickup)
    await input.open(this.claimPrimeStream(deviceId, reduceMusicPickup))
    return input
  }

  // The probe stream from requestPermission, handed over when the first input
  // wants the same device with the same constraints. Claimed at most once.
  claimPrimeStream(deviceId, reduceMusicPickup) {
    const stream = this.primeStream
    if (!stream || reduceMusicPickup) return null

    const track = stream.getAudioTracks()[0]
    if (!track || track.readyState !== "live") {
      this.primeStream = null
      return null
    }
    if (deviceId && track.getSettings?.().deviceId !== deviceId) return null

    this.primeStream = null
    return stream
  }

  // Called once every input is open: a probe nobody claimed must not keep the
  // browser's recording indicator lit.
  releasePrimeStream() {
    this.primeStream?.getTracks().forEach((track) => track.stop())
    this.primeStream = null
  }

  onDeviceChange(callback) {
    this.deviceChangeHandler = () => callback()
    navigator.mediaDevices?.addEventListener?.("devicechange", this.deviceChangeHandler)
  }

  stopWatchingDevices() {
    if (!this.deviceChangeHandler) return

    navigator.mediaDevices?.removeEventListener?.("devicechange", this.deviceChangeHandler)
    this.deviceChangeHandler = null
  }
}

export class MicInput extends EventTarget {
  constructor(context, deviceId, reduceMusicPickup = false) {
    super()
    this.context = context
    this.deviceId = deviceId
    this.reduceMusicPickup = reduceMusicPickup
    this.frames = []
    this.level = 0
    this.stream = null
    this.nodes = []
    this.lost = false
  }

  // existingStream, when given, is an already-open stream for this device (the
  // permission probe) — adopted instead of asking the browser again.
  async open(existingStream = null) {
    if (existingStream) {
      this.stream = existingStream
    } else {
      const audio = { ...SINGING_CONSTRAINTS, echoCancellation: this.reduceMusicPickup }
      if (this.deviceId) audio.deviceId = { exact: this.deviceId }

      this.stream = await navigator.mediaDevices.getUserMedia({ audio })
    }

    const source = this.context.createMediaStreamSource(this.stream)
    const pitchNode = new AudioWorkletNode(this.context, "karaoke-pitch-processor")
    pitchNode.port.onmessage = (event) => this.#onFrame(event.data)

    // The worklet never plays anything back — it only measures — but a node
    // that reaches no destination is never pulled, so route it through a
    // silent gain rather than leaving it dangling.
    const sink = this.context.createGain()
    sink.gain.value = 0
    source.connect(pitchNode)
    pitchNode.connect(sink)
    sink.connect(this.context.destination)

    this.nodes = [ source, pitchNode, sink ]
    this.pitchNode = pitchNode

    this.stream.getAudioTracks()[0]?.addEventListener("ended", () => {
      this.lost = true
      this.dispatchEvent(new CustomEvent("ended"))
    })

    return this
  }

  #onFrame(frame) {
    this.frames.push(frame)
    this.level = this.level + (Math.min(1, frame.rms * 12) - this.level) * LEVEL_SMOOTHING
    this.dispatchEvent(new CustomEvent("frame", { detail: frame }))
  }

  // Everything captured since the last call. The engine drains once per
  // animation frame, so a stalled main thread delays scoring but never drops
  // a sample or misplaces it in time.
  drainFrames() {
    if (this.frames.length === 0) return EMPTY

    const frames = this.frames
    this.frames = []
    return frames
  }

  setGates({ rmsGate, correlationThreshold }) {
    this.pitchNode?.port.postMessage({ rmsGate, correlationThreshold })
  }

  // Listen to the room for a moment — ideally with the music playing — and
  // gate a few times above whatever is bleeding in.
  measureNoiseFloor(seconds = 2) {
    return new Promise((resolve) => {
      const samples = []
      const onFrame = (event) => samples.push(event.detail.rms)
      this.addEventListener("frame", onFrame)

      setTimeout(() => {
        this.removeEventListener("frame", onFrame)
        const floor = samples.length > 0 ? samples.reduce((sum, value) => sum + value, 0) / samples.length : 0
        const gate = Math.max(MIN_RMS_GATE, floor * NOISE_FLOOR_MULTIPLIER)
        this.setGates({ rmsGate: gate })
        resolve({ floor, gate })
      }, seconds * 1000)
    })
  }

  close() {
    this.stream?.getTracks().forEach((track) => track.stop())
    this.nodes.forEach((node) => node.disconnect())
    this.nodes = []
    this.stream = null
    this.pitchNode = null
    this.frames = []
  }
}

const EMPTY = []
