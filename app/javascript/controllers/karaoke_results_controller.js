import { Controller } from "@hotwired/stimulus"

// The scoreboard shown when a song finishes: a grade per singer, what made it
// up, and how the performance went line by line.
export default class extends Controller {
  static targets = [
    "heading", "song", "singers", "spark", "leaderboard", "leaderboardList",
    "nextUp", "nextUpArt", "nextUpSong", "nextUpBy", "nextUpNote", "nextUpCount"
  ]

  static LEADERBOARD_LIMIT = 10

  static GRADE_HEADINGS = {
    S: "Outstanding!",
    A: "Great singing!",
    B: "Nice one!",
    C: "Keep practising!",
    D: "Tough one — try again?"
  }

  connect() {
    // ??=, not =: the coordinator assigns this from its outlet callback, and
    // Stimulus does not promise that callback runs after this controller has
    // connected. When it ran first, connect() wiped the delegate — and every
    // control here goes through it, so the screen came up with dead buttons
    // about one load in ten.
    this.delegate ??= null
    this.countdown = null
    this.remaining = 0
  }

  disconnect() {
    this.clearCountdown()
  }

  // results: { track, singers: [{ name, color, score, grade, accuracy,
  //   notesHit, notesTotal, goldenHit, goldenTotal, bestCombo, bestLine,
  //   lineAccuracies, personalBest, bestScore }] }
  show(results) {
    // The coordinator adds the hand-off after this, if there is one. Clearing
    // it here means a leftover countdown from the last song can never survive
    // into a panel that has nothing queued behind it.
    this.hideNextUp()

    const singers = results.singers || []
    const leader = singers.reduce((best, singer) => (!best || singer.score > best.score ? singer : best), null)

    this.headingTarget.textContent = this.constructor.GRADE_HEADINGS[leader?.grade] || "Nice one!"
    this.songTarget.textContent = results.track ? `${results.track.title} — ${results.track.artist}` : ""

    this.singersTarget.innerHTML = singers
      .map((singer) => this.singerMarkup(singer, singers.length > 1 && singer === leader))
      .join("")

    this.renderSparkline(singers)
    this.loadLeaderboard(results.track, singers)
  }

  // The song's all-time list, fetched fresh each time so it already includes
  // the scores this performance just posted. Names persist per browser (the
  // setup screen saves them), so tonight's singers can be picked out of it.
  async loadLeaderboard(track, singers) {
    this.leaderboardTarget.hidden = true
    if (!track?.isrc) return

    let payload = null
    try {
      const response = await fetch(`/api/karaoke/${encodeURIComponent(track.isrc)}/scores`)
      payload = response.ok ? await response.json() : null
    } catch {
      return // the scoreboard works fine without it
    }

    const best = (payload?.best || []).slice(0, this.constructor.LEADERBOARD_LIMIT)
    if (best.length === 0) return

    const local = new Set(singers.map((singer) => singer.name))
    this.leaderboardListTarget.innerHTML = best
      .map((row, index) => `
        <li class="karaoke-leaderboard__row${local.has(row.singer_name) ? " is-you" : ""}">
          <span class="rank">${index + 1}</span>
          <span class="name">${this.escape(row.singer_name)}</span>
          <span class="points">${this.number(row.score)}</span>
        </li>
      `)
      .join("")
    this.leaderboardTarget.hidden = false
  }

  singerMarkup(singer, isWinner) {
    const grade = (singer.grade || "D").toLowerCase()
    const best = singer.personalBest
      ? `<p class="karaoke-scoreboard__best is-new">New personal best!</p>`
      : `<p class="karaoke-scoreboard__best">Best: ${this.number(singer.bestScore)}</p>`

    return `
      <div class="karaoke-scoreboard__singer" style="--singer-color: ${this.escapeAttribute(singer.color)}">
        <span class="karaoke-scoreboard__crown" ${isWinner ? "" : "hidden"} aria-label="Winner">👑</span>
        <span class="karaoke-scoreboard__name"><i></i>${this.escape(singer.name)}</span>
        <p class="karaoke-scoreboard__grade karaoke-scoreboard__grade--${grade}">${this.escape(singer.grade || "D")}</p>
        <p class="karaoke-scoreboard__score">${this.number(singer.score)}</p>
        ${best}
        <dl class="karaoke-scoreboard__stats">
          ${this.stat("Pitch accuracy", `${Math.round((singer.accuracy || 0) * 100)}%`)}
          ${this.stat("Notes hit", `${singer.notesHit || 0} / ${singer.notesTotal || 0}`)}
          ${this.stat("Golden notes", `${singer.goldenHit || 0} / ${singer.goldenTotal || 0}`)}
          ${this.stat("Best streak", `${singer.bestCombo || 0} lines`)}
        </dl>
        ${singer.bestLine ? `<p class="karaoke-scoreboard__quote">Best line: <q>${this.escape(singer.bestLine.text)}</q></p>` : ""}
      </div>
    `
  }

  stat(label, value) {
    return `<div class="karaoke-scoreboard__stat"><dt>${this.escape(label)}</dt><dd>${this.escape(value)}</dd></div>`
  }

  // One polyline per singer over the song's lines. No axes and no hover: the
  // exact numbers are in the stats above, this is only the shape.
  renderSparkline(singers) {
    this.sparkTarget.querySelectorAll(".spark-line").forEach((line) => line.remove())

    singers.forEach((singer, index) => {
      const values = singer.lineAccuracies || []
      if (values.length < 2) return

      const points = values
        .map((value, position) => {
          const x = (position / (values.length - 1)) * 100
          const y = 27 - Math.max(0, Math.min(1, value)) * 25
          return `${x.toFixed(2)},${y.toFixed(2)}`
        })
        .join(" ")

      const line = document.createElementNS("http://www.w3.org/2000/svg", "polyline")
      line.setAttribute("class", `spark-line spark-line--p${index + 1}`)
      line.setAttribute("vector-effect", "non-scaling-stroke")
      line.setAttribute("points", points)
      this.sparkTarget.appendChild(line)
    })
  }

  // --- The queue hand-off ----------------------------------------------------

  // The countdown lives here rather than in the coordinator so what the screen
  // says and what is about to happen can never disagree: one timer, and it is
  // the one being displayed.
  showNextUp(item, seconds) {
    this.clearCountdown()

    this.nextUpArtTarget.src = item.image_url || ""
    this.nextUpSongTarget.textContent = `${item.title} — ${item.artist}`
    this.nextUpByTarget.textContent = item.added_by ? ` · added by ${item.added_by}` : ""
    // Not a warning: it is why a song queued a minute ago can still be sung
    // when it comes up.
    this.nextUpNoteTarget.hidden = Boolean(item.ready)
    this.nextUpTarget.hidden = false

    this.remaining = seconds
    this.renderCountdown()
    this.countdown = setInterval(() => {
      this.remaining -= 1
      this.renderCountdown()
      if (this.remaining <= 0) this.#handOff({ unattended: true })
    }, 1000)
  }

  hideNextUp() {
    this.clearCountdown()
    if (this.hasNextUpTarget) this.nextUpTarget.hidden = true
  }

  renderCountdown() {
    this.nextUpCountTarget.textContent = this.remaining > 0 ? `${this.remaining}s` : "Starting…"
  }

  clearCountdown() {
    clearInterval(this.countdown)
    this.countdown = null
  }

  // The button under the hand-off. Somebody is standing at the screen, so the
  // song it starts stops at its setup screen — see the coordinator's
  // resultsStartNext.
  startNext() {
    this.#handOff({ unattended: false })
  }

  // unattended says whether anyone is known to be watching: the countdown
  // running out is the case nobody is, and the only one where the next song
  // may start itself.
  #handOff({ unattended }) {
    this.clearCountdown()
    this.renderCountdown()
    this.delegate?.resultsStartNext?.({ unattended })
  }

  skipNext() {
    this.clearCountdown()
    this.delegate?.resultsSkipNext?.()
  }

  // --- Actions ---------------------------------------------------------------

  // Both of these are a decision to stay on this song, or leave entirely —
  // either way the queue's countdown must stop running underneath them.
  singAgain() {
    this.hideNextUp()
    this.delegate?.resultsSingAgain?.()
  }

  back() {
    this.hideNextUp()
    this.delegate?.resultsBack?.()
  }

  number(value) {
    return Number(value || 0).toLocaleString()
  }

  escape(value) {
    return String(value ?? "").replace(/[&<>]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[char]))
  }

  escapeAttribute(value) {
    return this.escape(value).replace(/"/g, "&quot;")
  }
}
