import { Controller } from "@hotwired/stimulus"
import { PitchLane } from "karaoke/pitch_lane"

// The karaoke stage: what the engine's animation-frame loop renders into.
//
// THE FRAME CONTRACT — the engine calls, once per frame, with a REUSED object
// (do not retain it):
//
//   frame({
//     time, duration,
//     line: { index, sweep /* 0..1 */, wordIndex, next },
//     held,                                    // hold this note
//     countIn: null | { kind: "initial"|"gap", secondsRemaining, digit },
//     singers: [ { midi, voiced, level, score, combo } ]
//   })
//
// and out of band:
//
//   setLines(lines)                 // [{ text, singer, words }]
//   setNotes(melody, scores)        // forwarded to the pitch lane
//   lineVerdict(singerIndex, verdict)
//
// Everything in frame() is dirty-checked, and the only things written per
// frame are CSS custom properties, canvas draws, and text that actually
// changed. There are no layout reads in the frame path: the one measurement
// this controller makes (fitting a long line) happens on a line swap, roughly
// every few seconds.
export default class extends Controller {
  static targets = [
    "backdrop", "time", "song",
    "chip", "chipName", "chipScore", "chipCombo",
    "lane", "canvas",
    "verdict",
    "dots", "partBadge", "skip", "activeLine", "activeBase", "activeFill", "nextLine",
    "countIn", "countRing", "countDigit",
    "controlbar", "playButton", "currentTime", "duration", "seek",
    "fader", "faderInput", "melodyToggle", "fullscreenButton",
    "syncInput", "syncValue", "monitorInput"
  ]

  // How long the control bar stays up after the mouse stops moving.
  static CONTROLS_IDLE_MS = 3000
  // A line shrunk below this is unreadable from a sofa; let it wrap instead.
  static MIN_FIT = 0.55
  // How long a finished line stays at full strength before fading back.
  static PAST_LINE_SECONDS = 1.5

  connect() {
    this.lines = []
    this.renderedLine = -1
    this.renderedSweep = -1
    this.renderedSecond = -1
    this.renderedDigit = null
    this.renderedCountKind = null
    this.renderedHeld = false
    this.renderedPast = false
    this.renderedSkip = false
    this.renderedScores = [ null, null ]
    this.renderedCombos = [ null, null ]
    this.controlsTimer = null
    this.lane = null
    this.singerColors = [ "#22d3ee", "#a78bfa" ]
    this.pointerDown = false
    this.wakeLock = null
    this.delegate = null

    this.boundPointerMove = () => this.showControls()
    this.boundKeydown = (event) => this.onKeydown(event)
    this.boundFullscreenChange = () => this.syncFullscreenButton()
    this.boundVisibility = () => this.reacquireWakeLock()

    this.boundPointerRelease = () => { this.pointerDown = false }

    this.element.addEventListener("pointermove", this.boundPointerMove)
    // Shown on the *down* half of the tap: on a touch screen there is no
    // pointermove first, and a bar that only appears on pointerup swallows
    // the tap that was meant for its buttons.
    this.element.addEventListener("pointerdown", () => { this.pointerDown = true; this.showControls() })
    this.element.addEventListener("pointerup", () => this.showControls())
    // The release is watched on the window, not the stage: let go outside the
    // element — or have the browser cancel the pointer, which going full
    // screen can do — and the stage's own pointerup never comes. The flag
    // would stay set, and a set flag means the bar never hides again.
    window.addEventListener("pointerup", this.boundPointerRelease)
    window.addEventListener("pointercancel", this.boundPointerRelease)
    document.addEventListener("keydown", this.boundKeydown)
    document.addEventListener("fullscreenchange", this.boundFullscreenChange)
    document.addEventListener("visibilitychange", this.boundVisibility)
  }

  disconnect() {
    this.element.removeEventListener("pointermove", this.boundPointerMove)
    window.removeEventListener("pointerup", this.boundPointerRelease)
    window.removeEventListener("pointercancel", this.boundPointerRelease)
    document.removeEventListener("keydown", this.boundKeydown)
    document.removeEventListener("fullscreenchange", this.boundFullscreenChange)
    document.removeEventListener("visibilitychange", this.boundVisibility)
    clearTimeout(this.controlsTimer)
    this.lane?.dispose()
    this.lane = null
    this.releaseWakeLock()
  }

  // --- Entering and leaving ------------------------------------------------

  // Called from inside the Start click. requestFullscreen has to run in that
  // gesture's own turn of the event loop, so this must not be awaited on
  // anything beforehand.
  enter({ track, singers, hasVocals, vocalPercent, guideMelody, latencyTrimMs = 0, monitorPercent = 0 }) {
    this.requestFullscreen()

    this.songTarget.textContent = `${track.title} — ${track.artist}`
    this.backdropTarget.src = track.image_url || ""
    this.element.dataset.singers = String(singers.length)
    this.singerColors = this.distinctColors(singers)
    // Indexed by part - 1, and empty on a song nobody split: that is what
    // keeps a solo performance from growing a name badge over every line.
    this.partNames = singers.map((singer) => (singer.part ? singer.name : null))
    this.lane?.setColors({ singers: this.singerColors })

    singers.forEach((singer, index) => {
      const number = index + 1
      this.element.style.setProperty(`--p${number}`, this.singerColors[index])
      const chip = this.chipFor(number)
      if (chip) {
        chip.hidden = false
        chip.style.setProperty("--chip-color", singer.color)
      }
      this.targetFor("chipName", number).textContent = singer.name
      this.targetFor("chipScore", number).textContent = "0"
      this.targetFor("chipCombo", number).textContent = ""
    })
    for (let number = singers.length + 1; number <= 2; number++) {
      const chip = this.chipFor(number)
      if (chip) chip.hidden = true
    }

    this.faderTarget.hidden = !hasVocals
    this.faderInputTarget.value = vocalPercent
    this.melodyToggleTarget.setAttribute("aria-pressed", String(Boolean(guideMelody)))
    this.syncInputTarget.value = latencyTrimMs
    this.syncValueTarget.textContent = this.formatTrim(latencyTrimMs)
    this.setMonitorPercent(monitorPercent)

    this.resetRenderState()
    this.acquireWakeLock()
    this.showControls()
  }

  leave() {
    this.releaseWakeLock()
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {})
    this.resetRenderState()
  }

  resetRenderState() {
    this.renderedLine = -1
    this.renderedSweep = -1
    this.renderedSecond = -1
    this.renderedDigit = null
    this.renderedCountKind = null
    this.renderedHeld = false
    this.renderedPast = false
    this.renderedSkip = false
    this.renderedScores = [ null, null ]
    this.renderedCombos = [ null, null ]
    this.activeBaseTarget.textContent = ""
    this.activeFillTarget.textContent = ""
    this.nextLineTarget.textContent = ""
    if (this.hasPartBadgeTarget) this.partBadgeTarget.hidden = true
    if (this.hasSkipTarget) { this.skipTarget.hidden = true; this.renderedSkip = false }
    this.activeLineTarget.classList.remove("karaoke-lyric--past")
    this.countInTarget.hidden = true
    this.countInTarget.classList.remove("is-go")
    this.dotsTarget.hidden = true
  }

  // --- The engine's view ---------------------------------------------------

  setLines(lines) {
    this.lines = lines || []
    this.renderedLine = -1
    if (this.lines.length === 0) {
      this.activeBaseTarget.textContent = "No synced lyrics for this song."
      this.activeFillTarget.textContent = ""
    }
  }

  // A song with no usable melody keeps its lane — the row has to stay, or the
  // lyric block would stop being anchored to the bottom — it just draws
  // nothing.
  // scores defaults to keeping whatever the lane already has: a caller that
  // omits it must not be able to silently strip the lane of its scorers.
  setNotes(melody, scores = this.lane?.scores) {
    // Without a melody the lane would sit there as a large empty band with the
    // lyrics stranded under it, so the layout gives its space back instead.
    this.element.dataset.lane = !melody || melody.isEmpty ? "off" : "on"

    this.lane ||= new PitchLane(this.canvasTarget, this.laneTarget)
    this.lane.setColors({ singers: this.singerColors })
    this.lane.resize()
    this.lane.setMelody(melody)
    this.lane.setScores(scores)
  }

  frame(state) {
    if (state.line.index !== this.renderedLine) this.swapLines(state.line.index)

    // The wipe. One custom property, resolved by clip-path — no layout, no
    // paint outside the line's own containing block.
    const sweep = Math.round(state.line.sweep * 1000) / 10
    if (sweep !== this.renderedSweep) {
      this.activeLineTarget.style.setProperty("--sweep", `${sweep}%`)
      this.renderedSweep = sweep
    }

    if (state.held !== this.renderedHeld) {
      this.activeLineTarget.classList.toggle("karaoke-lyric--held", state.held)
      this.renderedHeld = state.held
    }

    // A line that finished a while ago fades back, so it stops reading as the
    // singer's current cue during an instrumental break.
    const line = this.lines[state.line.index]
    const past = Boolean(line) && state.time > line.endTime + this.constructor.PAST_LINE_SECONDS
    if (past !== this.renderedPast) {
      this.activeLineTarget.classList.toggle("karaoke-lyric--past", past)
      this.renderedPast = past
    }

    this.renderCountIn(state.countIn)
    this.renderSkip(state.skip)
    this.renderClock(state)
    this.renderScores(state.singers)
    this.lane?.frame(state.time, state.singers)
  }

  swapLines(index) {
    const line = this.lines[index]
    const next = this.lines[index + 1]

    this.activeBaseTarget.textContent = line ? line.text : ""
    this.activeFillTarget.textContent = line ? line.text : ""
    this.nextLineTarget.textContent = next ? next.text : ""

    // Who sings what, said three ways: the line is tinted, the line coming up
    // is tinted, and the singer is named over the top. One colour difference
    // on the wipe was too easy to miss from across a room — and it only
    // arrived as the line was already being sung, which is too late to be a
    // cue about whose turn it is.
    this.paintPart(this.activeLineTarget, line?.singer ?? null)
    this.paintPart(this.nextLineTarget, next?.singer ?? null)
    this.renderPartBadge(line?.singer ?? null)

    this.activeLineTarget.style.setProperty("--sweep", "0%")
    this.renderedSweep = 0
    this.activeLineTarget.classList.remove("karaoke-lyric--past")
    this.renderedPast = false

    this.fitLine()
    this.retrigger(this.activeLineTarget, "is-in")

    this.renderedLine = index
  }

  // Long lines shrink rather than wrap: a wrapped line would put two rows of
  // text under one horizontal wipe. Costs one layout read per line.
  fitLine() {
    const needed = this.activeBaseTarget.scrollWidth
    const available = this.activeLineTarget.parentElement.clientWidth
    if (!needed || !available) return

    const fit = Math.min(1, available / needed)
    this.activeLineTarget.style.setProperty("--fit", Math.max(this.constructor.MIN_FIT, fit).toFixed(3))
    this.activeLineTarget.style.whiteSpace = fit < this.constructor.MIN_FIT ? "normal" : "nowrap"
  }

  // Digit 0 is the "GO" beat the engine holds just past the line's start: the
  // overlay plays its exit animation there (ending at opacity 0), so the
  // eventual hidden toggle is invisible and the countdown never just blinks
  // out. Gap dots get the same treatment through their data-remaining="0"
  // fade.
  renderCountIn(countIn) {
    const kind = countIn?.kind ?? null

    if (kind !== this.renderedCountKind) {
      this.countInTarget.hidden = kind !== "initial"
      this.dotsTarget.hidden = kind !== "gap"
      this.countInTarget.classList.remove("is-go")
      this.renderedCountKind = kind
      this.renderedDigit = null
    }

    if (!countIn) return

    if (countIn.digit !== this.renderedDigit) {
      this.renderedDigit = countIn.digit
      if (kind === "initial") {
        if (countIn.digit === 0) {
          this.countDigitTarget.textContent = "GO!"
          this.countInTarget.classList.add("is-go")
        } else {
          // Seeking back into the intro re-arms the count-in; the GO state
          // must not linger over the fresh digits.
          this.countInTarget.classList.remove("is-go")
          this.countDigitTarget.textContent = String(countIn.digit)
          this.retrigger(this.countDigitTarget, "is-popping")
          this.retrigger(this.countRingTarget, "is-ticking")
        }
      } else {
        this.dotsTarget.dataset.remaining = String(countIn.digit)
      }
    }
  }

  renderClock(state) {
    const second = Math.floor(Math.max(0, state.time))
    if (second !== this.renderedSecond) {
      const formatted = this.formatTime(state.time)
      this.timeTarget.textContent = formatted
      this.currentTimeTarget.textContent = formatted
      this.durationTarget.textContent = this.formatTime(state.duration)
      this.renderedSecond = second
    }

    if (state.duration > 0) {
      const progress = Math.max(0, state.time) / state.duration
      this.element.style.setProperty("--progress", progress.toFixed(4))
      if (document.activeElement !== this.seekTarget && !this.pointerDown) {
        this.seekTarget.value = progress * 1000
      }
    }
  }

  renderScores(singers) {
    singers?.forEach((singer, index) => {
      const number = index + 1

      const score = Math.round(singer.score || 0)
      if (score !== this.renderedScores[index]) {
        const element = this.targetFor("chipScore", number)
        if (element) element.textContent = score.toLocaleString()
        this.renderedScores[index] = score
      }

      const combo = singer.combo || 0
      if (combo !== this.renderedCombos[index]) {
        const element = this.targetFor("chipCombo", number)
        if (element) {
          element.textContent = combo >= 2 ? `×${combo}` : ""
          if (combo >= 2) this.retrigger(element, "is-bumped")
        }
        this.renderedCombos[index] = combo
      }
    })
  }

  // Two singers must never be painted the same colour. The tinted line, the
  // name badge, the score chips and the pitch trails all rest on the
  // difference, and a stored setup can still hold a duplicate from before the
  // setup screen repaired them. Falls back to the stage's own palette rather
  // than trusting what it was handed.
  distinctColors(singers) {
    const chosen = singers.map((singer) => singer.color)
    if (new Set(chosen).size === chosen.length) return chosen

    const styles = getComputedStyle(this.element)
    return chosen.map((colour, index) => styles.getPropertyValue(`--karaoke-singer-${index + 1}`).trim() || colour)
  }

  // Shown while a long instrumental stretch is running. Its own state is a
  // single boolean, so it is only touched when that flips — this runs sixty
  // times a second.
  renderSkip(skip) {
    if (!this.hasSkipTarget) return

    const offered = Boolean(skip)
    if (offered === this.renderedSkip) return

    this.renderedSkip = offered
    this.skipTarget.hidden = !offered
  }

  skipInstrumental() {
    this.delegate?.stageSkipInstrumental?.()
  }

  paintPart(element, part) {
    element.classList.toggle("karaoke-lyric--p1", part === 1)
    element.classList.toggle("karaoke-lyric--p2", part === 2)
  }

  // The name of whoever this line belongs to, over the line itself. Hidden
  // outright on a song with no parts, rather than showing a blank chip.
  renderPartBadge(part) {
    if (!this.hasPartBadgeTarget) return

    const name = part ? this.partNames?.[part - 1] : null
    this.partBadgeTarget.hidden = !name
    if (!name) return

    this.partBadgeTarget.textContent = name
    this.partBadgeTarget.className = `karaoke-cue__part karaoke-cue__part--p${part}`
  }

  // Perfect / Great / Good / Miss, popped above the singer's side of the
  // screen. One persistent element each, so they can never collide.
  lineVerdict(singerIndex, verdict) {
    const element = this.targetFor("verdict", singerIndex + 1)
    if (!element) return

    element.textContent = verdict.charAt(0).toUpperCase() + verdict.slice(1)
    element.className = `karaoke-verdict karaoke-verdict--p${singerIndex + 1} karaoke-verdict--${verdict}`
    this.retrigger(element, "is-shown")
  }

  // --- Controls ------------------------------------------------------------

  togglePlay() {
    this.delegate?.stageTogglePlay?.()
  }

  seek() {
    this.delegate?.stageSeek?.(this.seekTarget.value / 1000)
  }

  changeVocalGuide() {
    this.delegate?.stageVocalGuide?.(Number(this.faderInputTarget.value))
  }

  // The latency trim, adjustable without leaving the song — sync problems are
  // noticed mid-line, not on the setup screen. The engine reads the setting
  // every frame, so the change is heard immediately.
  changeSync() {
    const trim = Number(this.syncInputTarget.value)
    this.syncValueTarget.textContent = this.formatTrim(trim)
    this.delegate?.stageLatency?.(trim)
  }

  formatTrim(ms) {
    return `${ms > 0 ? "+" : ""}${ms} ms`
  }

  // How loud the singers hear themselves. Raised mid-song more often than not:
  // a level that sounded right in a quiet room is a different thing once the
  // backing track is under it.
  changeMonitor() {
    this.delegate?.stageMicMonitor?.(Number(this.monitorInputTarget.value))
  }

  // Also called when the setup screen moves the same setting, so the two
  // faders can never disagree.
  setMonitorPercent(percent) {
    if (this.hasMonitorInputTarget) this.monitorInputTarget.value = percent
  }

  toggleMelody() {
    const on = this.melodyToggleTarget.getAttribute("aria-pressed") !== "true"
    this.melodyToggleTarget.setAttribute("aria-pressed", String(on))
    this.delegate?.stageGuideMelody?.(on)
  }

  exit() {
    this.delegate?.stageExit?.()
  }

  setPlaying(playing) {
    this.playButtonTarget.textContent = playing ? "⏸" : "▶"
  }

  onKeydown(event) {
    if (this.element.offsetParent === null) return // stage isn't the visible screen
    // The scoreboard is over the stage; replaying from under it would run the
    // song to its end again and post a second score.
    if (this.element.closest(".karaoke")?.classList.contains("karaoke--results")) return
    if (event.code !== "Space") return

    const tag = document.activeElement?.tagName
    if (tag === "INPUT" || tag === "BUTTON" || tag === "SELECT") return

    event.preventDefault()
    this.togglePlay()
  }

  showControls() {
    this.element.classList.add("is-controls-visible")
    this.element.classList.remove("is-idle")
    clearTimeout(this.controlsTimer)

    this.controlsTimer = setTimeout(() => {
      // Never yank the bar away mid-drag, or out from under the keyboard.
      if (this.pointerDown || this.keyboardIsOnTheBar()) return this.showControls()

      this.element.classList.remove("is-controls-visible")
      this.element.classList.add("is-idle")
    }, this.constructor.CONTROLS_IDLE_MS)
  }

  // Whether somebody is working the bar with the keyboard, which is the only
  // focus worth holding it open for.
  //
  // :focus-within is not that test. A mouse click leaves focus on the button
  // it hit, so one press of pause — or one nudge of the sync slider — used to
  // pin the bar open, and every frame of the song after that was sung with a
  // control bar across the bottom of the screen and a mouse cursor on top of
  // it. :focus-visible is the browser's own answer to "was this focus reached
  // by keyboard", which is exactly the question being asked.
  keyboardIsOnTheBar() {
    const focused = document.activeElement
    if (!focused || !this.controlbarTarget.contains(focused)) return false

    // Safari only shipped :focus-visible for form controls late; a browser
    // that cannot answer keeps the old, safer behaviour of holding the bar.
    try {
      return focused.matches(":focus-visible")
    } catch {
      return true
    }
  }

  // --- Full screen and wake lock -------------------------------------------

  requestFullscreen() {
    const root = this.element.closest(".karaoke") || this.element
    root.requestFullscreen?.({ navigationUI: "hide" }).catch(() => {})
  }

  toggleFullscreen() {
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {})
    else this.requestFullscreen()
  }

  // The user can always escape out; show a way back in rather than fighting it.
  syncFullscreenButton() {
    this.fullscreenButtonTarget.hidden = Boolean(document.fullscreenElement)
  }

  async acquireWakeLock() {
    try {
      this.wakeLock = await navigator.wakeLock?.request("screen")
    } catch {
      this.wakeLock = null // denied or unsupported; the screen may dim
    }
  }

  releaseWakeLock() {
    this.wakeLock?.release().catch(() => {})
    this.wakeLock = null
  }

  // A wake lock is dropped whenever the page is hidden, so it has to be taken
  // again on the way back.
  reacquireWakeLock() {
    if (document.visibilityState === "visible" && !this.wakeLock && this.element.offsetParent !== null) {
      this.acquireWakeLock()
    }
  }

  // --- Helpers -------------------------------------------------------------

  chipFor(number) {
    return this.chipTargets.find((element) => element.dataset.singer === String(number))
  }

  targetFor(name, number) {
    return this[`${name}Targets`].find((element) => element.dataset.singer === String(number))
  }

  // Restarting a CSS animation needs the class removed, a reflow, then the
  // class back. Happens on line swaps and verdicts, about once a second at
  // most — nowhere near the per-frame path.
  retrigger(element, className) {
    element.classList.remove(className)
    void element.offsetWidth
    element.classList.add(className)
  }

  formatTime(seconds) {
    if (!Number.isFinite(seconds)) return "0:00"
    const total = Math.max(0, Math.floor(seconds))
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`
  }
}
