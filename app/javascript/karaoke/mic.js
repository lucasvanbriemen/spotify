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
  }

  // Device labels stay empty until permission has been given once, so the
  // picker has to ask before it can offer anything meaningful.
  async requestPermission() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: SINGING_CONSTRAINTS })
      stream.getTracks().forEach((track) => track.stop())
      this.granted = true
      return true
    } catch {
      this.granted = false
      return false
    }
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
    await input.open()
    return input
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

  async open() {
    const audio = { ...SINGING_CONSTRAINTS, echoCancellation: this.reduceMusicPickup }
    if (this.deviceId) audio.deviceId = { exact: this.deviceId }

    this.stream = await navigator.mediaDevices.getUserMedia({ audio })

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
