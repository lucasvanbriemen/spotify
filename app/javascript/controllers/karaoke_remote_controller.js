import { Controller } from "@hotwired/stimulus"
import { QueueApi } from "karaoke/queue_api"

// The phone remote: search, tap, and the song is lined up on the TV.
//
// It is the same queue the karaoke screen walks, so this controller does very
// little of its own — it searches, it adds, and it keeps showing what the room
// has coming, which is the part that makes handing your phone back feel safe.
export default class extends Controller {
  static targets = [ "name", "query", "results", "queue", "empty", "count", "shuffle", "nowPlaying", "status" ]
  static values = { pollMs: { type: Number, default: 4000 } }

  // Remembered per phone: whoever is holding it is the same person all
  // evening, and typing a name once per song would be the reason nobody used
  // this.
  static NAME_KEY = "karaoke.remote.name"
  static MIN_QUERY_LENGTH = 3
  static SEARCH_DEBOUNCE_MS = 350

  connect() {
    this.searchToken = 0
    this.searchDebounce = null
    this.pollTimer = null
    this.items = []

    this.nameTarget.value = this.savedName()

    this.boundVisibility = () => this.onVisibilityChange()
    document.addEventListener("visibilitychange", this.boundVisibility)

    this.startPolling()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.boundVisibility)
    clearTimeout(this.searchDebounce)
    this.stopPolling()
  }

  // --- The queue ------------------------------------------------------------

  startPolling() {
    this.stopPolling()
    this.tick()
  }

  async tick() {
    await this.refresh()
    this.pollTimer = setTimeout(() => this.tick(), this.pollMsValue)
  }

  stopPolling() {
    clearTimeout(this.pollTimer)
    this.pollTimer = null
  }

  // A phone left on a lock screen for an hour shouldn't spend that hour
  // polling — but it must be current the moment it is picked back up.
  onVisibilityChange() {
    if (document.hidden) this.stopPolling()
    else this.startPolling()
  }

  async refresh() {
    const payload = await QueueApi.list()

    if (!payload.ok) {
      // The usual cause is the join cookie having expired out from under the
      // page, which looks like a failed request rather than an error body.
      this.setStatus("Lost the queue — open the link on the karaoke screen again.")
      return
    }

    this.setStatus(null)
    this.apply(payload)
  }

  renderNowPlaying(item) {
    this.nowPlayingTarget.hidden = !item
    if (!item) return

    this.nowPlayingTarget.textContent = `Now singing: ${item.title} — ${item.artist}`
  }

  renderQueue() {
    this.countTarget.textContent = this.items.length === 0 ? "" : String(this.items.length)
    this.emptyTarget.hidden = this.items.length > 0
    this.shuffleTarget.hidden = this.items.length < 2

    this.queueTarget.innerHTML = this.items.map((item, index) => this.queueRow(item, index)).join("")
  }

  queueRow(item, index) {
    const by = item.added_by ? `<span class="karaoke-remote__by">${this.escape(item.added_by)}</span>` : ""

    // Removing is open to whoever is holding a phone, the same as reordering.
    // It used to be yours-only, matched on the name in the box above — which
    // meant a song queued under a name that had since been retyped could not
    // be taken off by anyone, and a song a phone had gone home with sat in the
    // queue all evening. Fixing the running order is the point, and a
    // "my songs only" version of it doesn't fix anything.
    //
    // A button with nothing to do at the end of the list keeps its place
    // (is-placeholder) instead of being dropped. On a phone that matters more
    // than the width it costs: dropping it slides every other control sideways,
    // so the same glyph sits at a different spot on each row and a thumb aimed
    // at ▼ lands on ⇤ instead.
    const title = this.escapeAttribute(item.title)
    const remove = `<button type="button" class="karaoke-rowbutton karaoke-remote__remove" data-id="${item.id}"
                 data-action="karaoke-remote#remove" aria-label="Remove ${title}">✕</button>`
    const step = (direction, glyph, label, atEnd) =>
      `<button type="button" class="karaoke-rowbutton${atEnd ? " is-placeholder" : ""}" data-id="${item.id}"
               data-direction="${direction}" data-action="karaoke-remote#move"
               aria-label="${label} ${title}">${glyph}</button>`

    return `
      <li class="karaoke-remote__queue-item">
        <span class="karaoke-remote__position">${index + 1}</span>
        <img class="karaoke-remote__art" src="${this.escapeAttribute(item.image_url)}" alt="">
        <span class="karaoke-remote__meta">
          <strong>${this.escape(item.title)}</strong>
          <span>${this.escape(item.artist)}${by}</span>
        </span>
        ${item.ready ? "" : `<span class="karaoke-remote__preparing">Preparing…</span>`}
        <span class="karaoke-remote__row-actions">
          ${step("up", "▲", "Move up", index === 0)}
          ${step("down", "▼", "Move down", index === this.items.length - 1)}
          <button type="button" class="karaoke-rowbutton${index === 0 ? " is-placeholder" : ""}" data-id="${item.id}"
                  data-action="karaoke-remote#promote" aria-label="Move ${title} to the front">⇤</button>
          ${remove}
        </span>
      </li>
    `
  }

  async remove(event) {
    this.apply(await QueueApi.remove(Number(event.currentTarget.dataset.id)))
  }

  async shuffle() {
    this.apply(await QueueApi.shuffle())
  }

  async move(event) {
    const { id, direction } = event.currentTarget.dataset
    this.apply(await QueueApi.move(Number(id), direction))
  }

  async promote(event) {
    this.apply(await QueueApi.promote(Number(event.currentTarget.dataset.id)))
  }

  // Every queue-changing call answers with the whole queue, so adopting the
  // response is both the optimistic update and the authoritative one — which
  // is what keeps a reorder from being undone by the next poll.
  apply(payload) {
    if (!payload.ok) return

    this.items = payload.items || []
    this.renderNowPlaying(payload.now_playing)
    this.renderQueue()
  }

  // --- Searching and adding -------------------------------------------------

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
    this.resultsTarget.dataset.searching = "true"

    const payload = await QueueApi.search(query)
    if (token !== this.searchToken) return // a newer keystroke superseded this one

    this.resultsTarget.dataset.searching = "false"
    if (!payload.ok) return this.setStatus("Search didn't come back — try again.")

    this.renderResults(payload.songs || [])
  }

  renderResults(songs) {
    this.resultsTarget.innerHTML = ""

    for (const song of songs) {
      const row = document.createElement("button")
      row.type = "button"
      row.className = "karaoke-remote__result"
      row.innerHTML = `
        <img src="${this.escapeAttribute(song.image_url)}" alt="">
        <span class="karaoke-remote__meta">
          <strong>${this.escape(song.title)}</strong>
          <span>${this.escape(song.artist)}</span>
        </span>
        <span class="karaoke-remote__add">${song.ready ? "Add" : "Add ⏳"}</span>
      `
      row.addEventListener("click", () => this.add(song, row))
      this.resultsTarget.appendChild(row)
    }
  }

  async add(song, row) {
    const label = row.querySelector(".karaoke-remote__add")
    label.textContent = "…"

    const payload = await QueueApi.add(song, this.nameTarget.value.trim())
    label.textContent = payload.ok ? "Queued ✓" : "Try again"

    if (!payload.ok) {
      if (payload.error) this.setStatus(payload.error)
      return
    }

    this.apply(payload)
  }

  // --- Name -----------------------------------------------------------------

  saveName() {
    try {
      localStorage.setItem(this.constructor.NAME_KEY, this.nameTarget.value.trim())
    } catch {
      // Private mode; the name just won't survive a reload.
    }
    // Nothing to re-render: the name is only what new rows are queued under.
    // It used to decide which rows showed a remove button, which is why
    // retyping it had to redraw the list.
  }

  savedName() {
    try {
      return localStorage.getItem(this.constructor.NAME_KEY) || ""
    } catch {
      return ""
    }
  }

  // --- Helpers --------------------------------------------------------------

  setStatus(message) {
    this.statusTarget.hidden = !message
    this.statusTarget.textContent = message || ""
  }

  escape(value) {
    return String(value ?? "").replace(/[&<>]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[char]))
  }

  escapeAttribute(value) {
    return this.escape(value).replace(/"/g, "&quot;")
  }
}
