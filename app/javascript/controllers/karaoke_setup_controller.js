import { Controller } from "@hotwired/stimulus"
import { MicSystem } from "karaoke/mic"
import { settings } from "karaoke/settings"

// Who is singing, in what colour, on which microphone — set up while the
// separation finishes in the background.
//
// Two singers means two separate input devices, each with its own pitch
// tracker, so both are scored independently while they sing at the same time.
// Sharing one device between them would score both on whoever was louder.
export default class extends Controller {
  static targets = [ "countOption", "singerCard", "name", "swatch", "device", "level", "check", "enableMics", "latency", "latencyValue" ]

  static DEFAULT_COLORS = [ "#22d3ee", "#a78bfa" ]
  // A sung note has to hold for about this long before the check passes, so a
  // cough or a chair scrape doesn't count.
  static CHECK_HOLD_MS = 300
  // Register detection: a rolling window of pitch frames (~5s at the
  // worklet's rate), refreshed in steps so the median isn't recomputed on
  // every frame.
  static REGISTER_WINDOW = 240
  static REGISTER_MIN_SAMPLES = 40

  connect() {
    this.delegate = null
    this.micSystem = null
    this.devices = []
    this.inputs = [ null, null ]
    this.levelFrame = null
    this.enabling = null
    this.registers = [ [], [] ]

    const saved = settings.get("singers") || []
    this.count = saved.length === 2 ? 2 : 1
    this.state = [ 0, 1 ].map((index) => ({
      name: saved[index]?.name || `Singer ${index + 1}`,
      color: saved[index]?.color || this.constructor.DEFAULT_COLORS[index],
      deviceId: saved[index]?.deviceId || null,
      // Labels survive the id rotation Safari and Firefox apply per session,
      // so a saved mic can be recognised even when its id can't.
      deviceLabel: saved[index]?.deviceLabel || null,
      // Median MIDI of what the mic check heard — how the guide melody knows
      // which octave this voice lives in.
      registerMidi: saved[index]?.registerMidi ?? null,
      passed: false
    }))

    this.renderLatency()
    this.render()
  }

  disconnect() {
    this.closeMics()
    if (this.levelFrame) cancelAnimationFrame(this.levelFrame)
  }

  reset() {
    this.state.forEach((singer) => { singer.passed = false })
    this.registers = [ [], [] ]
    this.checkTargets.forEach((element) => { element.textContent = ""; element.className = "karaoke-singer__check" })
    // A browser that remembers the grant shouldn't make anyone find the
    // button again on every song.
    this.maybeAutoEnable()
  }

  // Runs the whole mic flow unprompted when — and only when — the browser
  // reports the permission as already granted, so it can never surprise
  // anyone with a permission dialog.
  async maybeAutoEnable() {
    if (this.micSystem || this.enabling) return
    if (!(await MicSystem.permissionGranted())) return

    this.enableMics()
  }

  // A TV's own audio delay is invisible to the browser, so this is the only
  // way to line scoring up with what the singer actually hears.
  changeLatency() {
    settings.set("latencyTrimMs", Number(this.latencyTarget.value))
    this.renderLatency()
  }

  renderLatency() {
    if (!this.hasLatencyTarget) return

    const trim = settings.get("latencyTrimMs")
    this.latencyTarget.value = trim

    // Show what is actually being applied, not just the slider's own number:
    // the browser contributes its own output latency, and an unexplained
    // total is the hardest kind of sync problem to chase.
    const context = this.delegate?.session?.context
    const total = context ? Math.round(settings.displayOffsetSeconds(context) * 1000) : null
    const sign = (ms) => `${ms > 0 ? "+" : ""}${ms} ms`

    this.latencyValueTarget.textContent = total === null
      ? sign(trim)
      : `${sign(trim)} — lyrics shown ${total} ms behind the audio clock`
  }

  // --- Singer choices -------------------------------------------------------

  chooseCount(event) {
    this.count = Number(event.currentTarget.dataset.count)
    if (this.count === 1) this.closeMic(1)
    this.render()
    this.persist()
  }

  renameSinger(event) {
    const index = Number(event.currentTarget.dataset.singer) - 1
    this.state[index].name = event.currentTarget.value.trim() || `Singer ${index + 1}`
    this.persist()
  }

  chooseColour(event) {
    const index = Number(event.currentTarget.dataset.singer) - 1
    this.state[index].color = event.currentTarget.dataset.colour
    this.render()
    this.persist()
  }

  async chooseDevice(event) {
    const index = Number(event.currentTarget.dataset.singer) - 1
    const deviceId = event.currentTarget.value || null
    this.state[index].deviceId = deviceId
    this.state[index].deviceLabel = this.devices.find((device) => device.deviceId === deviceId)?.label || null
    this.render()
    this.persist()
    await this.openMic(index)
  }

  // --- Microphones ----------------------------------------------------------

  // Deduplicated: the click handler and maybeAutoEnable can both arrive while
  // a previous run is still awaiting the permission dialog, and two runs would
  // open every mic twice.
  enableMics() {
    this.enabling ||= this.#enableMics().finally(() => { this.enabling = null })
    return this.enabling
  }

  async #enableMics() {
    const session = await this.delegate?.audioSession?.()
    if (!session) {
      // The one failure that used to be silent: the button looked dead.
      this.checkTargets.forEach((element) => {
        element.textContent = "Audio couldn't start — reload the page and try again."
        element.className = "karaoke-singer__check is-warning"
      })
      return
    }

    this.micSystem = new MicSystem(session)
    const granted = await this.micSystem.requestPermission()

    if (!granted) {
      this.micSystem = null // next click must re-ask rather than give up forever
      this.checkTargets.forEach((element) => {
        element.textContent = "Microphone blocked — allow it in your browser to be scored."
        element.className = "karaoke-singer__check is-warning"
      })
      return
    }

    this.devices = await this.micSystem.listDevices()
    // Safari and Firefox rotate device ids between sessions; the label is the
    // stable half of what was saved. A device the browser has genuinely
    // forgotten (mic unplugged) must not stay selected, or opening it would
    // throw.
    this.state.forEach((singer) => {
      if (!singer.deviceId || this.devices.some((device) => device.deviceId === singer.deviceId)) return

      const byLabel = singer.deviceLabel && this.devices.find((device) => device.label === singer.deviceLabel)
      singer.deviceId = byLabel ? byLabel.deviceId : null
    })

    this.enableMicsTarget.hidden = true
    this.assignDefaultDevices()
    this.render()
    this.renderLatency() // the session exists now, so the real total can be shown

    for (let index = 0; index < this.count; index++) await this.openMic(index)
    this.micSystem.releasePrimeStream() // whatever the inputs didn't claim
    this.watchLevels()
  }

  // Two singers get different devices by default — the whole point is one mic
  // each.
  assignDefaultDevices() {
    for (let index = 0; index < this.count; index++) {
      if (this.state[index].deviceId) continue

      const taken = this.state.slice(0, index).map((singer) => singer.deviceId)
      const chosen = this.devices.find((device) => !taken.includes(device.deviceId)) || this.devices[0]
      this.state[index].deviceId = chosen?.deviceId || null
      this.state[index].deviceLabel = chosen?.label || null
    }
  }

  async openMic(index) {
    if (!this.micSystem || index >= this.count) return

    const deviceId = this.state[index].deviceId
    // Already listening on that very device — reopening would drop the noise
    // floor it measured and, on Safari, prompt again.
    if (deviceId && this.inputs[index]?.deviceId === deviceId && this.inputs[index].stream) return

    this.closeMic(index)
    if (!deviceId) return

    try {
      const input = await this.micSystem.createInput(deviceId, { reduceMusicPickup: settings.get("reduceMusicPickup") })
      this.inputs[index] = input
      input.addEventListener("ended", () => this.onMicLost(index))
      this.listenForSinging(index, input)
      // Measured now rather than in silence: whatever the mic can hear of the
      // room is exactly what the gate has to sit above.
      input.measureNoiseFloor(1.5)
    } catch {
      this.setCheck(index, "Couldn't open that microphone — pick another.", "is-warning")
    }
  }

  closeMic(index) {
    this.inputs[index]?.close()
    this.inputs[index] = null
  }

  closeMics() {
    this.inputs.forEach((_input, index) => this.closeMic(index))
    this.micSystem?.stopWatchingDevices()
  }

  onMicLost(index) {
    this.closeMic(index)
    this.state[index].passed = false
    this.setCheck(index, "Microphone disconnected.", "is-warning")
  }

  // The check passes on a sustained pitch, not a loud noise — that is what
  // tells the singer their mic is close enough to be tracked over the music.
  // The same frames tell us which octave this voice lives in, which is what
  // lets the guide melody play in the singer's register (any octave scores
  // the same, so the check copy stays quiet about it).
  listenForSinging(index, input) {
    let since = null

    input.addEventListener("frame", (event) => {
      const { hz } = event.detail
      if (!hz) { since = null; return }

      this.recordRegister(index, hz)

      since ??= performance.now()
      if (performance.now() - since < this.constructor.CHECK_HOLD_MS) return
      if (this.state[index].passed) return

      this.state[index].passed = true
      this.setCheck(index, "Sounds good — you're being picked up. Sing in whatever octave is comfortable.", "is-ok")
    })

    this.setCheck(index, "Sing a note to check your mic…", "")
  }

  recordRegister(index, hz) {
    const samples = this.registers[index]
    samples.push(69 + 12 * Math.log2(hz / 440))
    if (samples.length > this.constructor.REGISTER_WINDOW) samples.shift()
    if (samples.length < this.constructor.REGISTER_MIN_SAMPLES) return
    if (samples.length % this.constructor.REGISTER_MIN_SAMPLES !== 0) return // settle, don't churn

    const sorted = [ ...samples ].sort((a, b) => a - b)
    this.state[index].registerMidi = Math.round(sorted[(sorted.length - 1) >> 1])
    this.persist()
  }

  setCheck(index, message, modifier) {
    const element = this.targetFor("check", index + 1)
    if (!element) return

    element.textContent = message
    element.className = `karaoke-singer__check ${modifier}`.trim()
  }

  // One loop for both meters, rather than a listener writing styles per frame
  // per mic.
  watchLevels() {
    const tick = () => {
      this.levelFrame = requestAnimationFrame(tick)
      this.inputs.forEach((input, index) => {
        if (!input) return

        const element = this.targetFor("level", index + 1)
        element?.style.setProperty("--level", input.level.toFixed(3))
      })
    }
    if (!this.levelFrame) this.levelFrame = requestAnimationFrame(tick)
  }

  // --- Rendering ------------------------------------------------------------

  render() {
    this.countOptionTargets.forEach((option) => {
      option.setAttribute("aria-pressed", String(Number(option.dataset.count) === this.count))
    })

    this.singerCardTargets.forEach((card) => {
      const number = Number(card.dataset.singer)
      card.hidden = number > this.count
      card.style.setProperty("--singer-color", this.state[number - 1].color)
    })

    this.nameTargets.forEach((input) => {
      const singer = this.state[Number(input.dataset.singer) - 1]
      if (document.activeElement !== input) input.value = singer.name
    })

    this.swatchTargets.forEach((swatch) => {
      const index = Number(swatch.dataset.singer) - 1
      const colour = swatch.dataset.colour
      swatch.setAttribute("aria-pressed", String(this.state[index].color === colour))
      // Stop both singers ending up the same colour.
      const otherIndex = index === 0 ? 1 : 0
      swatch.disabled = this.count === 2 && this.state[otherIndex].color === colour
    })

    this.deviceTargets.forEach((select) => {
      const index = Number(select.dataset.singer) - 1
      if (this.devices.length === 0) return

      const taken = this.state.filter((_singer, other) => other !== index && other < this.count).map((singer) => singer.deviceId)
      select.innerHTML = this.devices
        .map((device) => {
          const disabled = taken.includes(device.deviceId) ? " disabled" : ""
          const selected = this.state[index].deviceId === device.deviceId ? " selected" : ""
          return `<option value="${device.deviceId}"${selected}${disabled}>${this.escape(device.label)}</option>`
        })
        .join("")
    })
  }

  persist() {
    settings.set("singers", this.state.slice(0, this.count).map((singer) => ({
      name: singer.name,
      color: singer.color,
      deviceId: singer.deviceId,
      deviceLabel: singer.deviceLabel,
      registerMidi: singer.registerMidi
    })))
  }

  // --- What the coordinator asks for ----------------------------------------

  singers() {
    return this.state.slice(0, this.count).map((singer) => ({
      name: singer.name, color: singer.color, deviceId: singer.deviceId, registerMidi: singer.registerMidi
    }))
  }

  micInputs() {
    return this.inputs.slice(0, this.count)
  }

  targetFor(name, number) {
    return this[`${name}Targets`].find((element) => element.dataset.singer === String(number))
  }

  escape(value) {
    return (value ?? "").replace(/[&<>"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[char]))
  }
}
