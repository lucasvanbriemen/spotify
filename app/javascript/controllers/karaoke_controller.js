import { Controller } from "@hotwired/stimulus"
import { KaraokeEngine } from "karaoke/engine"
import { LyricsTimeline } from "karaoke/lyrics_timing"
import { Melody } from "karaoke/melody"
import { Transport } from "karaoke/transport"
import { getAudioSession } from "karaoke/audio_session"
import { settings } from "karaoke/settings"

// Coordinates the karaoke flow: search -> setup -> stage -> results.
//
// It owns the song (search, preparation, lyrics), the audio (transport,
// engine) and the reporting, and hands rendering to the screen controllers it
// outlets into. The stage is what the engine's frame loop draws into; this
// controller never touches it per frame.
export default class extends Controller {
  static targets = [
    "query", "results",
    "recentSection", "recentList", "popularSection", "popularList",
    "art", "title", "artist", "playerStatus", "startButton",
    "stepDownload", "stepSeparate", "stepAnalyse"
  ]

  static outlets = [ "karaoke-stage", "karaoke-setup", "karaoke-results" ]
  static values = { workletUrl: String }

  // Matches the iOS app: searches under 3 characters are noise, not signal.
  static MIN_QUERY_LENGTH = 3
  static SEARCH_DEBOUNCE_MS = 300
  // A play under 5s is a skip/preview, not a listen (mirrors PlayerManager).
  static MIN_REPORTABLE_SECONDS = 5
  static STATUS_POLL_MS = 2000

  connect() {
    this.searchToken = 0
    this.secondsPlayed = 0
    this.playTimer = null
    this.pollTimer = null
    this.currentTrack = null
    this.artifacts = {}
    this.timeline = LyricsTimeline.empty()
    this.melody = Melody.empty()
    this.session = null
    this.transport = null
    this.engine = null
    this.loadingIsrc = null

    this.boundPageHide = () => this.reportPlay()
    window.addEventListener("pagehide", this.boundPageHide)

    this.loadHistory()
  }

  disconnect() {
    window.removeEventListener("pagehide", this.boundPageHide)
    this.stopPlayTimer()
    this.clearPollTimer()
    this.teardownPlayback()
    this.setup?.closeMics?.()
    this.session?.close()
    this.session = null
  }

  // The screen controllers call back into here rather than reaching for the
  // audio themselves.
  karaokeStageOutletConnected(outlet) {
    outlet.delegate = this
  }

  karaokeSetupOutletConnected(outlet) {
    outlet.delegate = this
  }

  karaokeResultsOutletConnected(outlet) {
    outlet.delegate = this
  }

  // Stimulus throws when a singular outlet is read before it connects, and
  // optional chaining doesn't help because the getter itself raises — so every
  // read goes through these.
  get stage() {
    return this.hasKaraokeStageOutlet ? this.karaokeStageOutlet : null
  }

  get setup() {
    return this.hasKaraokeSetupOutlet ? this.karaokeSetupOutlet : null
  }

  get scoreboard() {
    return this.hasKaraokeResultsOutlet ? this.karaokeResultsOutlet : null
  }

  showScreen(name) {
    this.element.dataset.screen = name
    this.element.classList.remove("karaoke--results")
  }

  // --- Search ---------------------------------------------------------

  search() {
    clearTimeout(this.searchDebounce)
    const query = this.queryTarget.value.trim()

    if (query.length < this.constructor.MIN_QUERY_LENGTH) {
      this.resultsTarget.innerHTML = ""
      return
    }

    this.searchDebounce = setTimeout(() => this.runSearch(query), this.constructor.SEARCH_DEBOUNCE_MS)
  }

  async runSearch(query) {
    const token = ++this.searchToken
    const payload = await this.fetchJson(`/api/karaoke-search?q=${encodeURIComponent(query)}`)

    if (token !== this.searchToken) return // a newer keystroke already superseded this request

    if (!payload) {
      this.resultsTarget.innerHTML = ""
      return
    }

    this.renderInto(this.resultsTarget, payload.songs)
  }

  async loadHistory() {
    const payload = await this.fetchJson("/api/karaoke-history")
    if (!payload) return

    this.recentSectionTarget.hidden = payload.recent.length === 0
    this.popularSectionTarget.hidden = payload.most_sung.length === 0
    this.renderInto(this.recentListTarget, payload.recent)
    this.renderInto(this.popularListTarget, payload.most_sung)
  }

  renderInto(list, songs) {
    list.innerHTML = ""

    for (const song of songs) {
      const item = document.createElement("li")
      item.className = "results-item"
      item.tabIndex = 0
      item.innerHTML = `
        <img src="${this.escapeAttribute(song.image_url)}">
        <div class="meta">
          <h2>${this.escapeText(song.title)}</h2>
          <p>${this.escapeText(song.artist)}</p>
        </div>
        <span class="k_badges">${this.badgeMarkup(song)}</span>
      `
      item.addEventListener("click", () => this.selectSong(song))
      item.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") { event.preventDefault(); this.selectSong(song) }
      })
      list.appendChild(item)
    }
  }

  // A prepared song starts immediately; everything else needs a Demucs run.
  badgeMarkup(song) {
    const badges = []
    if (song.ready) badges.push(`<span class="karaoke-badge karaoke-badge--ready">Ready</span>`)
    if (song.difficulty) {
      badges.push(`<span class="karaoke-badge karaoke-badge--${this.escapeAttribute(song.difficulty)}">${this.escapeText(song.difficulty)}</span>`)
    }
    return badges.join("")
  }

  // --- Selecting a song ---------------------------------------------------

  selectSong(song) {
    this.reportPlay()
    this.stopPlayTimer()
    this.clearPollTimer()
    this.teardownPlayback()

    this.currentTrack = song
    this.artifacts = {}
    this.timeline = LyricsTimeline.empty()
    this.melody = Melody.empty()

    this.artTarget.src = song.image_url || ""
    this.titleTarget.textContent = song.title
    this.artistTarget.textContent = song.artist
    this.startButtonTarget.disabled = true

    this.showScreen("setup")
    this.setup?.reset?.()

    this.loadSongData(song.isrc)
    this.prepare(song.isrc)
  }

  back() {
    this.reportPlay()
    this.stopPlayTimer()
    this.clearPollTimer()
    this.teardownPlayback()
    this.stage?.leave?.()
    this.currentTrack = null

    this.showScreen("search")
    this.queryTarget.focus()
    this.loadHistory()
  }

  prepare(isrc) {
    this.setStep("download", "active")
    this.playerStatusTarget.textContent = "Preparing karaoke track…"
    fetch(`/api/karaoke/${encodeURIComponent(isrc)}/prepare`, { method: "POST" }).catch(() => {})
    this.pollStatus(isrc)
  }

  async pollStatus(isrc) {
    if (this.currentTrack?.isrc !== isrc) return // superseded by another selection

    const payload = await this.fetchJson(`/api/karaoke/${encodeURIComponent(isrc)}/status`)
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
      this.artifacts = payload.artifacts || {}
      this.setStep("download", "done")
      this.setStep("separate", "done")
      this.setStep("analyse", "done")
      this.playerStatusTarget.textContent = "Ready!"
      // Start stays disabled until the audio is decoded and playable — see
      // #loadTrack. Separation being finished is not the same as ready to sing.
      // The melody and word timings only exist once separation has finished,
      // so the copies fetched when the song was picked were 404s. Fetch them
      // again now, or this song would play with no pitch lane and no scoring.
      this.loadSongData(isrc)
      // Decoding a few minutes of audio takes a second or two; get it done
      // while the singers are still choosing names.
      this.preload(isrc)
      return
    }

    if (payload.stage === "separating") {
      this.setStep("download", "done")
      this.setStep("separate", "active")
      this.playerStatusTarget.textContent = "Removing vocals — this can take several minutes the first time…"
    } else {
      this.setStep("download", "active")
      this.playerStatusTarget.textContent = "Downloading original track…"
    }

    this.pollTimer = setTimeout(() => this.pollStatus(isrc), this.constructor.STATUS_POLL_MS)
  }

  setStep(name, state) {
    const target = { download: this.stepDownloadTarget, separate: this.stepSeparateTarget, analyse: this.stepAnalyseTarget }[name]
    target?.classList.toggle("is-active", state === "active")
    target?.classList.toggle("is-done", state === "done")
  }

  clearPollTimer() {
    clearTimeout(this.pollTimer)
    this.pollTimer = null
  }

  // --- Playback ------------------------------------------------------------

  // The setup screen needs the same context the music will play on, so its
  // mic pitch estimates share one clock with playback.
  // The promise is cached, not its result: the setup screen and the preloader
  // both ask for this, and caching only the resolved value lets a second
  // caller arriving mid-await build a whole second AudioContext — which would
  // put the mics on a different clock from the music and quietly break every
  // score.
  async audioSession() {
    this.sessionPromise ||= getAudioSession(this.workletUrlValue).catch(() => null)
    this.session = await this.sessionPromise
    return this.session
  }

  // Returns a promise that resolves only once the audio is actually decoded
  // and playable. Callers await the same promise rather than short-circuiting
  // on a "load has started" flag — otherwise pressing Start mid-load returns
  // instantly and play() no-ops against an empty buffer, leaving a full-screen
  // stage frozen at 0:00 with no error.
  preload(isrc) {
    if (this.loadingIsrc === isrc && this.loadPromise) return this.loadPromise

    this.loadingIsrc = isrc
    this.loadPromise = this.#loadTrack(isrc)
    return this.loadPromise
  }

  async #loadTrack(isrc) {
    await this.audioSession()
    if (!this.session || this.currentTrack?.isrc !== isrc) {
      // Leaving loadingIsrc set here would wedge this song forever.
      this.loadingIsrc = null
      return false
    }

    const transport = new Transport(this.session.context)
    transport.addEventListener("progress", (event) => {
      const { loaded, total } = event.detail
      if (total > 0 && this.currentTrack?.isrc === isrc) {
        this.playerStatusTarget.textContent = `Loading ${Math.min(99, Math.round((loaded / total) * 100))}%`
      }
    })
    transport.addEventListener("loaded", () => {
      if (this.currentTrack?.isrc === isrc) this.playerStatusTarget.textContent = "Ready!"
    })
    transport.addEventListener("loaderror", () => {
      if (this.currentTrack?.isrc === isrc) this.playerStatusTarget.textContent = "Couldn't load the instrumental for this song."
    })
    transport.addEventListener("play", () => { this.stage?.setPlaying?.(true); this.startPlayTimer() })
    transport.addEventListener("pause", () => { this.stage?.setPlaying?.(false); this.stopPlayTimer() })
    transport.addEventListener("ended", () => this.onSongEnded())

    this.transport = transport
    transport.setVocalGain(this.artifacts.vocals ? settings.get("vocalGuidePercent") / 100 : 0)

    const loaded = await transport.load({
      instrumentalUrl: `/api/karaoke/${encodeURIComponent(isrc)}/instrumental`,
      vocalsUrl: this.artifacts.vocals ? `/api/karaoke/${encodeURIComponent(isrc)}/vocals` : null
    })

    if (loaded && this.currentTrack?.isrc === isrc) this.startButtonTarget.disabled = false
    return loaded
  }

  // Bound to "Start singing" rather than fired automatically: preparation can
  // take minutes, long past the point where the browser still counts this as a
  // user gesture. The click is also what lets us go full screen and start the
  // audio context.
  async beginPlayback() {
    const track = this.currentTrack
    if (!track) return

    const singers = this.setup?.singers?.() || [ { name: "Singer 1", color: "#22d3ee", deviceId: null } ]
    this.currentSingers = singers

    // Both of these must happen inside the click's own turn of the event loop:
    // requestFullscreen is only allowed while the gesture is live.
    this.showScreen("stage")
    this.stage?.enter?.({
      track,
      singers,
      hasVocals: Boolean(this.artifacts.vocals),
      vocalPercent: settings.get("vocalGuidePercent"),
      guideMelody: settings.get("guideMelody")
    })

    await this.preload(track.isrc)
    if (!this.transport || this.currentTrack?.isrc !== track.isrc) return

    await this.session?.ensureRunning()

    this.engine = new KaraokeEngine({ transport: this.transport, settings, view: this.stage })
    this.engine.loadSong({ timeline: this.timeline, melody: this.melody, singers })
    this.engine.setMics(this.setup?.micInputs?.() || [])
    // loadSong already handed the stage its lines and notes — including the
    // scorers the pitch lane needs to fill hit notes in. Repeating setNotes
    // here without them would leave the lane unable to show anything but grey.
    this.engine.setGuideMelody(settings.get("guideMelody"))
    this.engine.start()

    // Songs that start singing almost immediately get a run-up: the clock
    // starts before the audio does, so the count-in has somewhere to happen.
    const firstStart = this.timeline.firstStart ?? 0
    this.transport.play({ preRollSeconds: firstStart >= 3.5 ? 0 : Math.max(0, 3 - firstStart) })
  }

  async onSongEnded() {
    this.stage?.setPlaying?.(false)
    this.reportPlay()
    this.stopPlayTimer()

    const results = this.engine?.results() || []
    // No mic means every note reads as silence, which would post a legitimate
    // -looking zero and show a scoreboard full of misses for someone who was
    // only listening.
    const scored = (this.setup?.micInputs?.() || []).some(Boolean)
    if (results.length === 0 || this.melody.isEmpty || !scored) return

    const singers = await Promise.all(results.map((result) => this.saveScore(result)))
    this.scoreboard?.show?.({ track: this.currentTrack, singers })
    this.element.classList.add("karaoke--results")
  }

  // The response carries the personal-best comparison, which is why this is a
  // fetch rather than a beacon.
  async saveScore(result) {
    const body = {
      singer_name: result.name,
      score: result.score,
      accuracy: result.accuracy,
      meta: {
        grade: result.grade,
        line_accuracies: result.lineAccuracies,
        notes_hit: result.notesHit,
        notes_total: result.notesTotal,
        golden_hit: result.goldenHit,
        golden_total: result.goldenTotal,
        best_combo: result.bestCombo,
        vocal_guide_percent: settings.get("vocalGuidePercent"),
        latency_trim_ms: settings.get("latencyTrimMs")
      }
    }

    try {
      const response = await fetch(`/api/karaoke/${encodeURIComponent(this.currentTrack.isrc)}/scores`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      })
      const saved = response.ok ? await response.json() : null
      return { ...result, personalBest: saved?.personal_best, bestScore: saved?.best_score ?? result.score }
    } catch {
      return { ...result, personalBest: false, bestScore: result.score }
    }
  }

  teardownPlayback() {
    this.engine?.destroy()
    this.engine = null
    this.transport?.destroy()
    this.transport = null
    this.loadingIsrc = null
  }

  // --- Called by the stage --------------------------------------------------

  stageTogglePlay() {
    if (!this.transport) return

    if (this.transport.playing) this.transport.pause()
    else this.transport.play()
  }

  stageSeek(fraction) {
    if (!this.transport?.duration) return

    this.transport.seek(fraction * this.transport.duration)
  }

  stageVocalGuide(percent) {
    settings.set("vocalGuidePercent", percent)
    this.transport?.setVocalGain(percent / 100)
  }

  stageGuideMelody(on) {
    settings.set("guideMelody", on)
    this.engine?.setGuideMelody(on)
  }

  stageExit() {
    this.stage?.leave?.()
    this.back()
  }

  // --- Called by the scoreboard --------------------------------------------

  resultsSingAgain() {
    this.element.classList.remove("karaoke--results")
    // Without this the second run reuses scorers whose notes are all already
    // finalized: nothing accumulates, and the results screen re-posts the
    // first run's score a second time.
    this.engine?.resetScores()
    this.transport?.seek(0)

    const firstStart = this.timeline.firstStart ?? 0
    this.transport?.play({ preRollSeconds: firstStart >= 3.5 ? 0 : Math.max(0, 3 - firstStart) })
  }

  resultsBack() {
    this.back()
  }

  // --- Lyrics --------------------------------------------------------------

  // Lyrics, word timings and the melody all describe the same song, so they
  // are fetched together and the timeline is only built once — the melody
  // needs the lines to attach its notes to.
  async loadSongData(isrc) {
    const [ lyrics, words, notes ] = await Promise.all([
      this.fetchJson(`/api/song/${encodeURIComponent(isrc)}/lyrics`),
      this.fetchJson(`/api/karaoke/${encodeURIComponent(isrc)}/words`),
      this.fetchJson(`/api/karaoke/${encodeURIComponent(isrc)}/notes`)
    ])

    if (this.currentTrack?.isrc !== isrc) return // superseded while in flight

    this.timeline = LyricsTimeline.parse(lyrics?.syncedLyrics || "", words)
    this.melody = Melody.parse(notes, this.timeline)

    // Reloading mid-performance would rebuild the scorers and wipe the score;
    // whatever is already on stage stays until the next song.
    if (this.transport?.playing) return

    this.engine?.loadSong({ timeline: this.timeline, melody: this.melody, singers: this.currentSingers || [] })
  }

  // --- Play reporting ------------------------------------------------------

  startPlayTimer() {
    this.stopPlayTimer()
    this.playTimer = setInterval(() => { this.secondsPlayed += 1 }, 1000)
  }

  stopPlayTimer() {
    clearInterval(this.playTimer)
    this.playTimer = null
  }

  // Fires on song switch, when a song ends, and on page unload — the app only
  // ever loses the very last play of a browser session, not every one.
  reportPlay() {
    const track = this.currentTrack
    const seconds = this.secondsPlayed
    this.secondsPlayed = 0

    if (!track || seconds < this.constructor.MIN_REPORTABLE_SECONDS) return

    const body = JSON.stringify({ isrc: track.isrc, seconds_played: seconds })
    navigator.sendBeacon("/api/plays", new Blob([ body ], { type: "application/json" }))
  }

  // --- Helpers -------------------------------------------------------------

  async fetchJson(url) {
    try {
      const response = await fetch(url)
      return response.ok ? await response.json() : null
    } catch {
      return null
    }
  }

  escapeText(value) {
    return (value ?? "").replace(/[&<>]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[char]))
  }

  escapeAttribute(value) {
    return this.escapeText(value).replace(/"/g, "&quot;")
  }
}
