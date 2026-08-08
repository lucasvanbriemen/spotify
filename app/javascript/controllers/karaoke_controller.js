import { Controller } from "@hotwired/stimulus"

// Search-as-you-type over /api/karaoke-search (only synced-lyrics tracks),
// then a full-screen lyrics stage synced to <audio> playback via LRC parsing.
// Playback is the vocal-free instrumental (see VocalSeparation), and a mic
// input, pitch-tracked in an AudioWorklet, is scored against the reference
// melody extracted from the original vocals.
export default class extends Controller {
  static targets = [
    "query", "searchStatus", "results",
    "searchPanel", "stage",
    "art", "title", "artist", "playerStatus", "lyrics", "startButton",
    "playButton", "seek", "currentTime", "duration", "audio",
    "score", "scoreMeterFill", "scoreValue", "scoreStatus"
  ]

  static values = { workletUrl: String }

  // Matches the iOS app: searches under 3 characters are noise, not signal.
  static MIN_QUERY_LENGTH = 3
  static SEARCH_DEBOUNCE_MS = 300
  // A play under 5s is a skip/preview, not a listen (mirrors PlayerManager).
  static MIN_REPORTABLE_SECONDS = 5
  static STATUS_POLL_MS = 2000
  // LRCLIB only gives one timestamp per line, not per word, so the last
  // line's end (and each word's share of its line) is estimated rather
  // than known — see prepareLines/wordIndexAtProgress.
  static LAST_LINE_FALLBACK_SECONDS = 4
  // Pitch-accuracy scoring band: full credit within a third of a semitone,
  // no credit a semitone and a half off, linear in between.
  static PERFECT_CENTS = 35
  static MISS_CENTS = 150
  static METER_SMOOTHING = 12 // rolling-average window, in frames, for the live meter (not the final score)

  connect() {
    this.searchToken = 0
    this.lines = []
    this.activeLineIndex = -1
    this.secondsPlayed = 0
    this.playTimer = null
    this.pollTimer = null
    this.currentTrack = null
    this.referencePitch = null
    this.livePitch = null
    this.micStream = null
    this.micContext = null
    this.scoreSamples = []
    this.meterSamples = []

    this.boundPageHide = () => this.reportPlay()
    window.addEventListener("pagehide", this.boundPageHide)
  }

  disconnect() {
    window.removeEventListener("pagehide", this.boundPageHide)
    this.stopPlayTimer()
    this.clearPollTimer()
    this.stopMic()
  }

  // --- Search ---------------------------------------------------------

  search() {
    clearTimeout(this.searchDebounce)
    const query = this.queryTarget.value.trim()

    if (query.length < this.constructor.MIN_QUERY_LENGTH) {
      this.resultsTarget.innerHTML = ""
      this.searchStatusTarget.textContent = ""
      return
    }

    this.searchStatusTarget.textContent = "Searching…"
    this.searchDebounce = setTimeout(() => this.runSearch(query), this.constructor.SEARCH_DEBOUNCE_MS)
  }

  async runSearch(query) {
    const token = ++this.searchToken

    let songs
    try {
      const response = await fetch(`/api/karaoke-search?q=${encodeURIComponent(query)}`)
      songs = (await response.json()).songs
    } catch {
      songs = null
    }

    if (token !== this.searchToken) return // a newer keystroke already superseded this request

    if (songs === null) {
      this.searchStatusTarget.textContent = "Search failed — check your connection and try again."
      this.resultsTarget.innerHTML = ""
      return
    }

    this.searchStatusTarget.textContent = songs.length === 0
      ? "No karaoke-ready songs found — try a more popular title."
      : ""
    this.renderResults(songs)
  }

  renderResults(songs) {
    this.resultsTarget.innerHTML = ""

    for (const song of songs) {
      const item = document.createElement("li")
      item.className = "karaoke-results__item"
      item.tabIndex = 0
      item.innerHTML = `
        <img src="${this.escapeAttribute(song.image_url)}" alt="" class="karaoke-results__art">
        <span class="karaoke-results__meta">
          <span class="karaoke-results__title">${this.escapeText(song.title)}</span>
          <span class="karaoke-results__artist">${this.escapeText(song.artist)}</span>
        </span>
      `
      item.addEventListener("click", () => this.selectSong(song))
      item.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") { event.preventDefault(); this.selectSong(song) }
      })
      this.resultsTarget.appendChild(item)
    }
  }

  // --- Selecting a song & preparing its karaoke track ---------------------

  selectSong(song) {
    this.reportPlay()
    this.stopPlayTimer()
    this.clearPollTimer()

    this.currentTrack = song
    this.lines = []
    this.activeLineIndex = -1
    this.referencePitch = null
    this.resetScoring()

    this.artTarget.src = song.image_url || ""
    this.titleTarget.textContent = song.title
    this.artistTarget.textContent = song.artist
    this.lyricsTarget.innerHTML = ""
    this.seekTarget.value = 0
    this.currentTimeTarget.textContent = "0:00"
    this.durationTarget.textContent = "0:00"
    this.playButtonTarget.textContent = "▶"
    this.startButtonTarget.hidden = true

    this.audioTarget.pause()
    this.audioTarget.removeAttribute("src")

    this.searchPanelTarget.hidden = true
    this.stageTarget.hidden = false

    this.loadLyrics(song.isrc)
    this.prepare(song.isrc)
  }

  back() {
    this.reportPlay()
    this.stopPlayTimer()
    this.clearPollTimer()
    this.audioTarget.pause()
    this.audioTarget.removeAttribute("src")
    this.audioTarget.load()
    this.currentTrack = null

    this.stageTarget.hidden = true
    this.searchPanelTarget.hidden = false
    this.queryTarget.focus()
  }

  prepare(isrc) {
    this.playerStatusTarget.textContent = "Preparing karaoke track…"
    fetch(`/api/karaoke/${encodeURIComponent(isrc)}/prepare`, { method: "POST" }).catch(() => {})
    this.pollStatus(isrc)
  }

  async pollStatus(isrc) {
    if (this.currentTrack?.isrc !== isrc) return // superseded by another selection

    let payload
    try {
      const response = await fetch(`/api/karaoke/${encodeURIComponent(isrc)}/status`)
      payload = response.ok ? await response.json() : null
    } catch {
      payload = null
    }

    if (this.currentTrack?.isrc !== isrc) return // superseded while the request was in flight

    if (!payload) {
      this.playerStatusTarget.textContent = "Couldn't reach the server — retrying…"
      this.pollTimer = setTimeout(() => this.pollStatus(isrc), this.constructor.STATUS_POLL_MS)
      return
    }

    if (payload.stage === "failed") {
      this.playerStatusTarget.textContent = "Couldn't prepare this song for karaoke — try another."
      return
    }

    if (payload.stage === "ready") {
      this.playerStatusTarget.textContent = "Ready!"
      this.startButtonTarget.hidden = false
      return
    }

    this.playerStatusTarget.textContent = payload.stage === "separating"
      ? "Removing vocals — this can take several minutes the first time…"
      : "Downloading original track…"
    this.pollTimer = setTimeout(() => this.pollStatus(isrc), this.constructor.STATUS_POLL_MS)
  }

  clearPollTimer() {
    clearTimeout(this.pollTimer)
    this.pollTimer = null
  }

  // --- Playback -------------------------------------------------------

  // Bound to the "Start singing" button rather than called automatically:
  // preparation can take minutes, long past the point where the browser
  // still considers this a user gesture, so autoplay would be blocked. A
  // fresh click here both starts playback and is the natural moment to ask
  // for the mic.
  beginPlayback() {
    const track = this.currentTrack
    if (!track) return

    this.startButtonTarget.hidden = true
    this.playerStatusTarget.textContent = ""

    const audio = this.audioTarget
    audio.src = `/api/karaoke/${encodeURIComponent(track.isrc)}/instrumental`

    audio.onwaiting = () => { this.playerStatusTarget.textContent = "Buffering…" }
    audio.oncanplay = () => { this.playerStatusTarget.textContent = "" }
    audio.onerror = () => { this.playerStatusTarget.textContent = "Couldn't load the instrumental for this song." }
    audio.onloadedmetadata = () => { this.durationTarget.textContent = this.formatTime(audio.duration) }
    audio.ontimeupdate = () => this.onTimeUpdate()
    audio.onplay = () => { this.playButtonTarget.textContent = "⏸"; this.startPlayTimer() }
    audio.onpause = () => { this.playButtonTarget.textContent = "▶"; this.stopPlayTimer() }
    audio.onended = () => { this.reportPlay(); this.stopPlayTimer(); this.showScoreSummary() }

    audio.play().catch(() => {})

    this.loadPitchCurve(track.isrc)
    this.startMic()
  }

  togglePlay() {
    if (this.audioTarget.paused) this.audioTarget.play().catch(() => {})
    else this.audioTarget.pause()
  }

  seek() {
    const audio = this.audioTarget
    if (!audio.duration) return
    audio.currentTime = (this.seekTarget.value / 1000) * audio.duration
  }

  onTimeUpdate() {
    const audio = this.audioTarget

    // Don't fight a slider the user is actively dragging.
    if (document.activeElement !== this.seekTarget && audio.duration) {
      this.seekTarget.value = (audio.currentTime / audio.duration) * 1000
    }
    this.currentTimeTarget.textContent = this.formatTime(audio.currentTime)

    this.updateActiveLine(audio.currentTime)
    this.updateScoring(audio.currentTime)
  }

  // --- Lyrics -----------------------------------------------------------

  async loadLyrics(isrc) {
    let payload
    try {
      const response = await fetch(`/api/song/${encodeURIComponent(isrc)}/lyrics`)
      payload = response.ok ? await response.json() : null
    } catch {
      payload = null
    }

    if (this.currentTrack?.isrc !== isrc) return // superseded by another selection while this was in flight

    const synced = payload?.syncedLyrics
    if (!synced) {
      this.lyricsTarget.innerHTML = `<p class="karaoke-lyrics__empty">No synced lyrics available for this song.</p>`
      return
    }

    this.lines = this.prepareLines(this.parseLRC(synced))
    this.activeLineIndex = -1
    this.renderLyrics()
  }

  // Mirrors the iOS app's LRC parser (Lyrics.swift): timestamps look like
  // [mm:ss], [mm:ss.xx] or [mm:ss:xx]; a line's text is everything after its
  // *last* timestamp, and a line can carry multiple timestamps (LRC
  // compression), each producing its own entry sharing that text.
  parseLRC(text) {
    const timestampPattern = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g
    const lines = []

    for (const rawLine of text.split("\n")) {
      const matches = [...rawLine.matchAll(timestampPattern)]
      if (matches.length === 0) continue

      const last = matches[matches.length - 1]
      const content = rawLine.slice(last.index + last[0].length).trim()
      if (!content) continue

      for (const match of matches) {
        const minutes = parseInt(match[1], 10)
        const seconds = parseInt(match[2], 10)
        const fraction = match[3] ? parseInt(match[3], 10) / (10 ** match[3].length) : 0
        lines.push({ time: minutes * 60 + seconds + fraction, text: content })
      }
    }

    return lines.sort((a, b) => a.time - b.time)
  }

  // Adds each line's word list and estimated end time (the next line's
  // start, or a fixed fallback for the last line) — everything
  // updateWordProgress needs to sweep a highlight across the words as the
  // line plays, since LRC only times whole lines.
  prepareLines(lines) {
    return lines.map((line, index) => {
      const words = line.text.split(/\s+/).filter(Boolean)
      // Character count is a rough stand-in for how long a word takes to
      // sing — not exact, but close enough to look right without real
      // per-word timing.
      const wordWeights = words.map((word) => word.length + 1)
      const endTime = index + 1 < lines.length ? lines[index + 1].time : line.time + this.constructor.LAST_LINE_FALLBACK_SECONDS
      return { ...line, words, wordWeights, endTime }
    })
  }

  renderLyrics() {
    this.lyricsTarget.innerHTML = this.lines
      .map((line, index) => {
        const words = line.words
          .map((word, wordIndex) => `<span class="karaoke-lyrics__word" data-word-index="${wordIndex}">${this.escapeText(word)}</span>`)
          .join(" ")
        return `<p class="karaoke-lyrics__line" data-index="${index}">${words}</p>`
      })
      .join("")
    this.lineElements = [...this.lyricsTarget.querySelectorAll(".karaoke-lyrics__line")]
  }

  // The active line is the last one whose timestamp has passed, matching
  // PlayerManager#currentLyricIndex(at:).
  updateActiveLine(currentTime) {
    let index = -1
    for (let i = 0; i < this.lines.length; i++) {
      if (this.lines[i].time <= currentTime) index = i
      else break
    }

    if (index !== this.activeLineIndex) {
      this.activeLineIndex = index
      this.lineElements?.forEach((el, i) => el.classList.toggle("karaoke-lyrics__line--active", i === index))
      if (index >= 0) this.lineElements[index].scrollIntoView({ behavior: "smooth", block: "center" })
    }

    if (index >= 0) this.updateWordProgress(index, currentTime)
  }

  // Sweeps a highlight across the active line's words, estimating position
  // within the line from elapsed time rather than true per-word timestamps
  // (see prepareLines).
  updateWordProgress(lineIndex, currentTime) {
    const line = this.lines[lineIndex]
    const wordEls = this.lineElements[lineIndex]?.querySelectorAll(".karaoke-lyrics__word")
    if (!wordEls || wordEls.length === 0) return

    const span = line.endTime - line.time
    const progress = span > 0 ? Math.max(0, Math.min(1, (currentTime - line.time) / span)) : 1
    const activeWordIndex = this.wordIndexAtProgress(line, progress)

    wordEls.forEach((el, i) => {
      el.classList.toggle("karaoke-lyrics__word--sung", i < activeWordIndex)
      el.classList.toggle("karaoke-lyrics__word--current", i === activeWordIndex)
    })
  }

  wordIndexAtProgress(line, progress) {
    const totalWeight = line.wordWeights.reduce((sum, weight) => sum + weight, 0)
    let cumulative = 0

    for (let i = 0; i < line.wordWeights.length; i++) {
      cumulative += line.wordWeights[i]
      if (progress <= cumulative / totalWeight) return i
    }
    return line.wordWeights.length - 1
  }

  // --- Mic capture & pitch tracking ---------------------------------------

  async startMic() {
    if (this.micStream) {
      this.scoreTarget.hidden = false // already granted this session — just reuse it
      return
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true }
      })

      const context = new AudioContext()
      await context.audioWorklet.addModule(this.workletUrlValue)

      const source = context.createMediaStreamSource(stream)
      const pitchNode = new AudioWorkletNode(context, "karaoke-pitch-processor")
      pitchNode.port.onmessage = (event) => { this.livePitch = event.data }

      // The worklet never plays audio back — it's only ever analyzed — but
      // its output still has to reach the destination or the graph is never
      // pulled, so route it through a silent gain instead of leaving it
      // disconnected.
      const silentSink = context.createGain()
      silentSink.gain.value = 0
      source.connect(pitchNode)
      pitchNode.connect(silentSink)
      silentSink.connect(context.destination)

      this.micStream = stream
      this.micContext = context
      this.scoreTarget.hidden = false
    } catch {
      this.scoreStatusTarget.textContent = "Mic access denied — allow it in your browser to get scored."
    }
  }

  stopMic() {
    this.micStream?.getTracks().forEach((track) => track.stop())
    this.micContext?.close()
    this.micStream = null
    this.micContext = null
    this.livePitch = null
  }

  // --- Scoring ------------------------------------------------------------

  async loadPitchCurve(isrc) {
    try {
      const response = await fetch(`/api/karaoke/${encodeURIComponent(isrc)}/pitch`)
      this.referencePitch = response.ok ? await response.json() : null
    } catch {
      this.referencePitch = null
    }
  }

  resetScoring() {
    this.scoreSamples = []
    this.meterSamples = []
    this.scoreTarget.hidden = true
    this.scoreStatusTarget.textContent = ""
    this.scoreValueTarget.textContent = ""
    this.scoreMeterFillTarget.style.width = "0%"
    this.scoreMeterFillTarget.style.background = ""
  }

  updateScoring(currentTime) {
    if (!this.micStream || !this.referencePitch) return

    const { hop_seconds, hz } = this.referencePitch
    const index = Math.round(currentTime / hop_seconds)
    const referenceHz = hz[index] ?? null
    const accuracy = this.scoreFrame(referenceHz, this.livePitch?.hz ?? null)

    if (accuracy !== null) this.scoreSamples.push(accuracy)
    this.updateMeter(accuracy)
  }

  // null (not scored — nothing to match) or 0..1, where 1 is dead-on and 0
  // is either far off pitch or silence when the reference expects singing.
  scoreFrame(referenceHz, liveHz) {
    if (referenceHz === null) return null
    if (liveHz === null) return 0

    // Fold to the nearest octave-equivalent distance so a singer in a
    // different register from the original vocal isn't penalized for it.
    let cents = 1200 * Math.log2(liveHz / referenceHz)
    cents = ((cents % 1200) + 1200) % 1200
    if (cents > 600) cents -= 1200
    const distance = Math.abs(cents)

    const { PERFECT_CENTS, MISS_CENTS } = this.constructor
    if (distance <= PERFECT_CENTS) return 1
    if (distance >= MISS_CENTS) return 0
    return 1 - (distance - PERFECT_CENTS) / (MISS_CENTS - PERFECT_CENTS)
  }

  updateMeter(accuracy) {
    this.meterSamples.push(accuracy ?? this.meterSamples.at(-1) ?? 0)
    if (this.meterSamples.length > this.constructor.METER_SMOOTHING) this.meterSamples.shift()

    const smoothed = this.meterSamples.reduce((sum, value) => sum + value, 0) / this.meterSamples.length
    this.scoreMeterFillTarget.style.width = `${Math.round(smoothed * 100)}%`
    this.scoreMeterFillTarget.style.background = smoothed >= 0.7 ? "var(--karaoke-good)" : smoothed >= 0.4 ? "var(--karaoke-ok)" : "var(--karaoke-bad)"

    if (this.scoreSamples.length > 0) {
      const overall = this.scoreSamples.reduce((sum, value) => sum + value, 0) / this.scoreSamples.length
      this.scoreValueTarget.textContent = `${Math.round(overall * 100)}%`
    }
  }

  showScoreSummary() {
    if (!this.micStream || this.scoreSamples.length === 0) return

    const percent = Math.round((this.scoreSamples.reduce((sum, value) => sum + value, 0) / this.scoreSamples.length) * 100)
    const verdict = percent >= 90 ? "Amazing!" : percent >= 70 ? "Nice one!" : percent >= 40 ? "Keep practicing!" : "Tough one — try again?"
    this.scoreStatusTarget.textContent = `Final score: ${percent}% — ${verdict}`
  }

  // --- Play reporting ---------------------------------------------------

  startPlayTimer() {
    this.stopPlayTimer()
    this.playTimer = setInterval(() => { this.secondsPlayed += 1 }, 1000)
  }

  stopPlayTimer() {
    clearInterval(this.playTimer)
    this.playTimer = null
  }

  // Fires on song switch, on <audio> "ended", and on page unload — the app
  // only ever loses the very last play of a browser session, not every one.
  reportPlay() {
    const track = this.currentTrack
    const seconds = this.secondsPlayed
    this.secondsPlayed = 0

    if (!track || seconds < this.constructor.MIN_REPORTABLE_SECONDS) return

    const body = JSON.stringify({ isrc: track.isrc, seconds_played: seconds })
    navigator.sendBeacon("/api/plays", new Blob([body], { type: "application/json" }))
  }

  // --- Helpers ------------------------------------------------------------

  formatTime(seconds) {
    if (!Number.isFinite(seconds)) return "0:00"
    const total = Math.max(0, Math.floor(seconds))
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`
  }

  escapeText(value) {
    return (value ?? "").replace(/[&<>]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[char]))
  }

  escapeAttribute(value) {
    return this.escapeText(value).replace(/"/g, "&quot;")
  }
}
