import { Controller } from "@hotwired/stimulus"

// The scoreboard shown when a song finishes: a grade per singer, what made it
// up, and how the performance went line by line.
export default class extends Controller {
  static targets = [ "heading", "song", "singers", "spark" ]

  static GRADE_HEADINGS = {
    S: "Outstanding!",
    A: "Great singing!",
    B: "Nice one!",
    C: "Keep practising!",
    D: "Tough one — try again?"
  }

  connect() {
    this.delegate = null
  }

  // results: { track, singers: [{ name, color, score, grade, accuracy,
  //   notesHit, notesTotal, goldenHit, goldenTotal, bestCombo, bestLine,
  //   lineAccuracies, personalBest, bestScore }] }
  show(results) {
    const singers = results.singers || []
    const leader = singers.reduce((best, singer) => (!best || singer.score > best.score ? singer : best), null)

    this.headingTarget.textContent = this.constructor.GRADE_HEADINGS[leader?.grade] || "Nice one!"
    this.songTarget.textContent = results.track ? `${results.track.title} — ${results.track.artist}` : ""

    this.singersTarget.innerHTML = singers
      .map((singer) => this.singerMarkup(singer, singers.length > 1 && singer === leader))
      .join("")

    this.renderSparkline(singers)
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

  singAgain() {
    this.delegate?.resultsSingAgain?.()
  }

  back() {
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
