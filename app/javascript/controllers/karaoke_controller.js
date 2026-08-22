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
    "readySection", "readyList",
    "recentSection", "recentList", "popularSection", "popularList",
    "art", "title", "artist", "playerStatus", "startButton", "retryButton",
    "stepDownload", "stepSeparate", "stepAnalyse"
  ]

  static outlets = [ "karaoke-stage", "karaoke-setup", "karaoke-results", "karaoke-queue" ]
  static values = { workletUrl: String }

  // Matches the iOS app: searches under 3 characters are noise, not signal.
  static MIN_QUERY_LENGTH = 3
  static SEARCH_DEBOUNCE_MS = 300
  // A play under 5s is a skip/preview, not a listen (mirrors PlayerManager).
  static MIN_REPORTABLE_SECONDS = 5
  static STATUS_POLL_MS = 2000
  // How long the scoreboard holds before the queue's next song takes over.
  // Long enough to read a score and reach for Skip, short enough that a room
  // that has walked away doesn't sit in silence.
  static NEXT_UP_SECONDS = 15

  connect() {
    this.searchToken = 0
    this.secondsPlayed = 0
    this.playTimer = null
    this.pollTimer = null
    this.currentTrack = null
    this.artifacts = {}
    this.alignmentOffset = 0
    this.timeline = LyricsTimeline.empty()
    this.melody = Melody.empty()
    this.session = null
    this.transport = null
    this.engine = null
    this.loadingIsrc = null
    // The queue row this song came from, and whether the song after it should
    // start on its own — a hand-off between two queued songs has nobody at the
    // screen to press Start.
    this.currentQueueItem = null
    this.autoStart = false

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

  karaokeQueueOutletConnected(outlet) {
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

  get queue() {
    return this.hasKaraokeQueueOutlet ? this.karaokeQueueOutlet : null
  }

  showScreen(name) {
    this.element.dataset.screen = name
    this.element.classList.remove("karaoke--results")
  }

  // --- Search ---------------------------------------------------------

  // The search form exists for semantics and the mobile keyboard's "search"
  // key; results arrive live from the input events, so an actual submission
  // has nowhere to go (there is no karaoke turbo frame) and would show
  // "content missing".
  suppressSubmit(event) {
    event.preventDefault()
  }

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

    const ready = payload.ready || []
    this.readySectionTarget.hidden = ready.length === 0
    this.recentSectionTarget.hidden = payload.recent.length === 0
    this.popularSectionTarget.hidden = payload.most_sung.length === 0
    this.renderInto(this.readyListTarget, ready)
    this.renderInto(this.recentListTarget, payload.recent)
    this.renderInto(this.popularListTarget, payload.most_sung)
  }

  renderInto(list, songs) {
    list.innerHTML = ""

    for (const song of songs) {
      const item = document.createElement("div")
      item.className = "result-item"
      // Focusable, or the Enter/Space handler below could never fire.
      item.tabIndex = 0
      item.setAttribute("role", "button")
      item.innerHTML = `
        <img src="${this.escapeAttribute(song.image_url)}">
        <div class="meta">
          <h2>${this.escapeText(song.title)}</h2>
          <p>${this.escapeText(song.artist)}</p>
        </div>
        <span class="badges">${this.badgeMarkup(song)}</span>
      `
      item.addEventListener("click", () => this.selectSong(song))
      item.addEventListener("keydown", (event) => {
        // The queue button below is inside the row and keyboard-operable in
        // its own right; without this, Enter on it would also sing the song.
        if (event.target !== item) return
        if (event.key === "Enter" || event.key === " ") { event.preventDefault(); this.selectSong(song) }
      })

      item.appendChild(this.queueButton(song))
      list.appendChild(item)
    }
  }

  // Tapping a result sings it now; this is how you say "after this one".
  // Built rather than templated so its click can be kept off the row's own.
  queueButton(song) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "result-item__queue"
    button.textContent = "+ Queue"
    button.setAttribute("aria-label", `Add ${song.title} to the queue`)

    button.addEventListener("click", async (event) => {
      event.stopPropagation() // the row itself starts the song
      const added = await this.queue?.add(song)
      button.textContent = added ? "Queued" : "Try again"
      setTimeout(() => { button.textContent = "+ Queue" }, 2000)
    })

    return button
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

  // queueItem/autoStart are only passed by the queue: a song handed over
  // between two queued numbers has to start itself, and has to remember which
  // row to mark as sung when it finishes.
  selectSong(song, { autoStart = false, queueItem = null } = {}) {
    this.reportPlay()
    this.stopPlayTimer()
    this.clearPollTimer()
    this.teardownPlayback()

    this.autoStart = autoStart
    this.currentQueueItem = queueItem
    this.currentTrack = song
    this.artifacts = {}
    this.alignmentOffset = 0
    this.timeline = LyricsTimeline.empty()
    this.melody = Melody.empty()

    this.artTarget.src = song.image_url || ""
    this.titleTarget.textContent = song.title
    this.artistTarget.textContent = song.artist
    this.startButtonTarget.disabled = true
    this.retryButtonTarget.hidden = true

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
    this.scoreboard?.hideNextUp?.()
    this.currentTrack = null
    // Walking out of a song is also a decision not to keep walking the queue.
    this.autoStart = false
    this.releaseQueueItem()

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
      // Nobody chose this one off a list, so nobody is watching to choose
      // again: a song the queue can't play must not end the evening.
      if (this.autoStart) this.skipToNextInQueue()
      return
    }

    if (payload.stage === "ready") {
      this.artifacts = payload.artifacts || {}
      // Non-zero when a YouTube instrumental runs behind the original the
      // timing data was made against; the engine shifts every clock by it.
      this.alignmentOffset = Number(payload.alignment_offset_seconds) || 0
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
    } else if (payload.stage === "queued") {
      // Enqueued but no worker has it yet. Worth saying out loud: only one song
      // is separated at a time, so a song picked while another is preparing
      // sits here for minutes with nothing to show — which read as a hung
      // download rather than a wait.
      this.setStep("download", "active")
      this.playerStatusTarget.textContent = "Waiting for another song to finish preparing…"
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
    // A promise that resolved to null is still truthy: without clearing it,
    // one failure (worklet 404, context refused) is cached for the life of
    // the page and every audio button stays silently dead.
    if (!this.session) this.sessionPromise = null
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

    // A retry after a failed load replaces the transport; the dead one's
    // nodes must not stay connected to the destination.
    this.transport?.destroy()

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
      if (this.currentTrack?.isrc === isrc) {
        this.playerStatusTarget.textContent = "Couldn't load the instrumental — press Retry."
        this.retryButtonTarget.hidden = false
      }
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

    // A failed load must not be cached, or the song is wedged until it is
    // re-selected; clearing lets Retry (and Start) attempt a fresh fetch.
    if (!loaded) {
      this.loadingIsrc = null
      this.loadPromise = null
    }

    if (loaded && this.currentTrack?.isrc === isrc) {
      this.startButtonTarget.disabled = false
      // The queue's hand-off waits here rather than on the status poll: a song
      // is ready to sing when its audio is decoded, not when separation ends.
      if (this.autoStart) {
        this.autoStart = false
        this.beginPlayback()
      }
    }
    return loaded
  }

  retryLoad() {
    const track = this.currentTrack
    if (!track) return

    this.retryButtonTarget.hidden = true
    this.playerStatusTarget.textContent = "Retrying…"
    this.preload(track.isrc)
  }

  // Bound to "Start singing" rather than fired automatically: preparation can
  // take minutes, long past the point where the browser still counts this as a
  // user gesture. The click is also what lets us go full screen and start the
  // audio context.
  async beginPlayback() {
    const track = this.currentTrack
    if (!track) return

    const singers = this.duetParts(this.setup?.singers?.() || [ { name: "Singer 1", color: "#22d3ee", deviceId: null } ])
    this.currentSingers = singers

    // Both of these must happen inside the click's own turn of the event loop:
    // requestFullscreen is only allowed while the gesture is live.
    this.showScreen("stage")
    this.stage?.enter?.({
      track,
      singers,
      hasVocals: Boolean(this.artifacts.vocals),
      vocalPercent: settings.get("vocalGuidePercent"),
      guideMelody: settings.get("guideMelody"),
      latencyTrimMs: settings.get("latencyTrimMs"),
      monitorPercent: settings.get("micMonitorPercent")
    })

    await this.preload(track.isrc)
    if (!this.transport || this.currentTrack?.isrc !== track.isrc) return

    await this.session?.ensureRunning()

    this.engine = new KaraokeEngine({ transport: this.transport, settings, view: this.stage })
    this.engine.setAlignmentOffset(this.alignmentOffset)
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
    this.releaseQueueItem()

    const results = this.engine?.results() || []
    // No mic means every note reads as silence, which would post a legitimate
    // -looking zero and show a scoreboard full of misses for someone who was
    // only listening.
    const scored = (this.setup?.micInputs?.() || []).some(Boolean)
    const scoreable = results.length > 0 && !this.melody.isEmpty && scored

    // Read after the row above was released, so the song that just finished
    // can't come back as its own successor.
    const next = await this.queue?.peekNext?.()
    if (!scoreable && !next) return

    const singers = scoreable ? await Promise.all(results.map((result) => this.saveScore(result))) : []
    // With nothing to score, the panel is only carrying the hand-off — but it
    // is still the right place for it: it is what is already over the stage.
    this.scoreboard?.show?.({ track: this.currentTrack, singers })
    this.element.classList.add("karaoke--results")

    if (next) this.scoreboard?.showNextUp?.(next, this.constructor.NEXT_UP_SECONDS)
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

  // The engine reads the trim from settings every frame, so writing it is the
  // whole job.
  stageLatency(ms) {
    settings.set("latencyTrimMs", ms)
    this.setup?.renderLatency?.()
  }

  // The PA fader on the control bar. The bus lives on the audio session, so
  // this survives the song it was set during.
  stageMicMonitor(percent) {
    settings.set("micMonitorPercent", percent)
    this.session?.monitor?.setLevel(percent)
    this.setup?.renderMonitor?.()
  }

  stageExit() {
    this.stage?.leave?.()
    this.back()
  }

  // --- Called by the setup screen ------------------------------------------

  // The monitor level, moved from the setup screen's copy of the fader. Told
  // to the stage so its own copy doesn't come back at a position that is no
  // longer true.
  monitorChanged(percent) {
    this.stage?.setMonitorPercent?.(percent)
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

  // The countdown ran out, or someone pressed Start now. Only the first of
  // those is unattended, and only an unattended song starts itself.
  resultsStartNext({ unattended = false } = {}) {
    this.playNextInQueue({ autoStart: unattended })
  }

  // Not for us, then. Whatever is behind it takes its place on the panel, so
  // Skip can be pressed twice in a row without the hand-off disappearing.
  async resultsSkipNext() {
    await this.queue?.dropNext?.()
    const next = await this.queue?.peekNext?.()

    if (next) this.scoreboard?.showNextUp?.(next, this.constructor.NEXT_UP_SECONDS)
  }

  // --- Called by the queue panel -------------------------------------------

  // "Play" on a queued song: it jumps the rest of the queue rather than being
  // played out of it, so nothing else is disturbed.
  //
  // It does NOT start itself. Pressing Play is someone choosing this song to
  // sing, and they need the setup screen the same as anyone who picked it out
  // of the search — it is where 1 or 2 singers is chosen, and who is on which
  // mic. Auto-starting straight past it let the screen show for about a second
  // before the song took over, which read as the choice not being offered.
  queuePlay(item) {
    this.startQueueItem(item)
  }

  // The queue panel polls; nothing here has to react to it changing. The hook
  // exists so a queue that empties while the scoreboard is counting down can
  // take its hand-off back.
  queueUpdated(items) {
    if (items.length === 0) this.scoreboard?.hideNextUp?.()
  }

  // --- Walking the queue ---------------------------------------------------

  // autoStart is the hand-off nobody is at the screen for; every other route
  // into the queue leaves the singers on the setup screen.
  async playNextInQueue({ autoStart = false } = {}) {
    const item = await this.queue?.claimNext?.()
    // The last song of the evening: stay on the scoreboard rather than
    // dropping the room back to a search box mid-applause.
    if (!item) return this.scoreboard?.hideNextUp?.()

    this.startQueueItem(item, { claimed: true, autoStart })
  }

  async startQueueItem(item, { claimed = false, autoStart = false } = {}) {
    if (!claimed) await this.queue?.claim?.(item)

    this.scoreboard?.hideNextUp?.()
    this.element.classList.remove("karaoke--results")
    this.selectSong(
      { isrc: item.isrc, title: item.title, artist: item.artist, image_url: item.image_url },
      { autoStart, queueItem: item }
    )
  }

  // A song the server can't prepare. Its row is already claimed, so releasing
  // it here is what keeps the queue moving instead of retrying it forever.
  skipToNextInQueue() {
    this.autoStart = false
    this.releaseQueueItem()
    // Only reached from a song that was itself auto-started, so whatever takes
    // its place has just as little reason to expect anyone at the screen.
    this.playNextInQueue({ autoStart: true })
  }

  // The song is off the stage — finished, skipped or walked out of. Either way
  // the row stops being the one being sung, or every phone in the room would
  // go on showing it.
  releaseQueueItem() {
    const item = this.currentQueueItem
    this.currentQueueItem = null
    if (item) this.queue?.markDone?.(item.id)

    return item
  }

  // --- Who is scored on what ------------------------------------------------

  // Two singers sharing one microphone cannot be told apart in the audio — a
  // receiver that mixes its two mics has already summed them, and pulling two
  // voices back out of one signal is not something a browser can do. The
  // lyrics can tell them apart though: a duet marks who takes which line, so
  // each singer is scored on their own lines off the shared input.
  //
  // With no markers there is nothing to separate them by, so they get one score
  // between them rather than two that would both track whoever sang loudest.
  duetParts(singers) {
    if (singers.length < 2) return singers

    const micOf = (singer, index) => singer.micIndex ?? index
    const sharing = singers.every((singer, index) => micOf(singer, index) === micOf(singers[0], 0))
    if (!sharing) return singers // a microphone each: scored independently, as before

    return this.duetMarked() ? singers.map((singer, index) => ({ ...singer, part: index + 1 })) : [ this.pairedSinger(singers) ]
  }

  // A duet is only separable when the lyrics name both parts. One marked part
  // is a lead vocal with a guest, not two singers taking turns.
  duetMarked() {
    const lines = this.timeline?.lines || []
    return [ 1, 2 ].every((part) => lines.some((line) => line.singer === part))
  }

  // One card for a pair on one mic. Named for both of them, so the scoreboard
  // doesn't quietly credit the performance to whoever was listed first.
  pairedSinger(singers) {
    return { ...singers[0], name: singers.map((singer) => singer.name).join(" & "), micIndex: 0, part: null }
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

    // The setup screen can only explain what sharing a microphone will mean for
    // this song once the lyrics are in — and they arrive here well before
    // anyone presses Start, since this runs as soon as the song is picked.
    this.setup?.setDuetMarkers?.(this.duetMarked())

    // Reloading mid-performance would rebuild the scorers and wipe the score;
    // whatever is already on stage stays until the next song. The exception:
    // a stage playing with NO melody (the fetch raced separation finishing)
    // has no score to wipe, and picking up the fresh notes is what turns its
    // pitch lane and scoring on at all.
    if (this.transport?.playing) {
      if (this.engine && this.engine.melody.isEmpty && !this.melody.isEmpty) {
        this.engine.loadSong({ timeline: this.timeline, melody: this.melody, singers: this.currentSingers || [] })
      }
      return
    }

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
      // "no-cache" revalidates rather than trusting the HTTP cache: the notes
      // and words endpoints are cached for a day, so a bad response once
      // cached (the X-Sendfile outage served empty 200s) would keep the pitch
      // lane blank for a day of retries. Revalidation makes that a cheap 304
      // when the artifact is unchanged and a fresh body when it isn't.
      const response = await fetch(url, { cache: "no-cache" })
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
