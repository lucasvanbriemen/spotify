import { Controller } from "@hotwired/stimulus"
import { QueueApi } from "karaoke/queue_api"

// The queue panel on the karaoke screen: what the room has lined up, who put
// it there, and the code a phone needs to add to it.
//
// It owns the polling. The queue changes on devices this page never hears
// from, so the only way the screen knows is by asking — and it keeps asking
// while anyone is looking at it, not while a song is playing.
//
// It is also the coordinator's only route to the queue rows: karaoke_controller
// asks it for the next song and tells it what happened to the last one, rather
// than fetching any of this itself.
export default class extends Controller {
  static targets = [ "list", "empty", "count", "clear", "copy" ]
  static values = {
    pollMs: { type: Number, default: 4000 },
    link: String
  }

  // What the screen calls itself when it queues a song, so a row added here is
  // still distinguishable from one a phone sent.
  static SCREEN_NAME = "Screen"

  connect() {
    this.delegate = null
    this.items = []
    this.nowPlaying = null
    this.pollTimer = null

    this.boundVisibility = () => this.onVisibilityChange()
    document.addEventListener("visibilitychange", this.boundVisibility)

    this.render()
    this.startPolling()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.boundVisibility)
    this.stopPolling()
  }

  // --- Polling --------------------------------------------------------------

  startPolling() {
    this.stopPolling()
    this.tick()
  }

  async tick() {
    // Only while the panel is on screen. During a song the coordinator asks
    // for what it needs (peekNext refreshes), and polling behind a full-screen
    // stage would be four requests a minute nobody reads.
    if (this.element.offsetParent !== null) await this.refresh()

    // Chained rather than an interval: a slow answer must not stack requests.
    this.pollTimer = setTimeout(() => this.tick(), this.pollMsValue)
  }

  stopPolling() {
    clearTimeout(this.pollTimer)
    this.pollTimer = null
  }

  // A backgrounded tab (the TV is showing something else) has nobody reading
  // the panel; picking straight back up on return is what matters.
  onVisibilityChange() {
    if (document.hidden) this.stopPolling()
    else this.startPolling()
  }

  async refresh() {
    const payload = await QueueApi.list()
    if (!payload.ok) return false

    this.adopt(payload)
    return true
  }

  adopt(payload) {
    this.items = payload.items || []
    this.nowPlaying = payload.now_playing || null
    this.render()
    this.delegate?.queueUpdated?.(this.items)
  }

  // --- What the coordinator asks for ----------------------------------------

  // Adds a song from the screen's own search results.
  async add(song) {
    const payload = await QueueApi.add(song, this.constructor.SCREEN_NAME)
    if (payload.ok) this.adopt(payload)

    return payload.ok
  }

  // The next song, re-read first: it may have been added, removed or reordered
  // from a phone since the last poll.
  async peekNext() {
    await this.refresh()
    return this.items[0] || null
  }

  // Takes the next song out of the waiting list and marks it as the one on
  // stage, so every phone in the room sees what is being sung.
  async claimNext() {
    const next = await this.peekNext()
    return next && this.claim(next)
  }

  async claim(item) {
    const payload = await QueueApi.setStatus(item.id, "playing")
    if (payload.ok) this.adopt(payload)

    return item
  }

  async markDone(id) {
    const payload = await QueueApi.setStatus(id, "done")
    if (payload.ok) this.adopt(payload)
  }

  // Used by the hand-off's Skip button: the song nobody wants leaves the queue
  // rather than staying at the front for the next song to trip over.
  async dropNext() {
    const next = this.items[0]
    if (!next) return null

    const payload = await QueueApi.remove(next.id)
    if (payload.ok) this.adopt(payload)

    return next
  }

  // --- Panel actions --------------------------------------------------------

  playNow(event) {
    const item = this.itemFor(event)
    if (item) this.delegate?.queuePlay?.(item)
  }

  async promote(event) {
    const item = this.itemFor(event)
    if (!item) return

    const payload = await QueueApi.promote(item.id)
    if (payload.ok) this.adopt(payload)
  }

  async remove(event) {
    const item = this.itemFor(event)
    if (!item) return

    const payload = await QueueApi.remove(item.id)
    if (payload.ok) this.adopt(payload)
  }

  async clear() {
    const payload = await QueueApi.clear()
    if (payload.ok) this.adopt(payload)
  }

  // The link carries the join code, so it is the one thing worth sending to a
  // phone that is already in a chat with you.
  async copyLink() {
    try {
      await navigator.clipboard.writeText(this.linkValue)
      this.flash(this.copyTarget, "Copied!")
    } catch {
      this.flash(this.copyTarget, "Copy failed")
    }
  }

  itemFor(event) {
    const id = Number(event.currentTarget.dataset.id)
    return this.items.find((item) => item.id === id) || null
  }

  // --- Rendering ------------------------------------------------------------

  render() {
    const count = this.items.length
    this.countTarget.textContent = count === 0 ? "" : String(count)
    this.emptyTarget.hidden = count > 0
    this.clearTarget.hidden = count === 0

    this.listTarget.innerHTML = this.items.map((item, index) => this.rowMarkup(item, index)).join("")
  }

  rowMarkup(item, index) {
    const by = item.added_by ? `<span class="karaoke-queue__by">${this.escape(item.added_by)}</span>` : ""
    // "Preparing" is not a warning — it is why a song that was queued a minute
    // ago can still be sung the moment it comes up.
    const state = item.ready
      ? `<span class="karaoke-badge karaoke-badge--ready">Ready</span>`
      : `<span class="karaoke-badge karaoke-badge--preparing">Preparing…</span>`

    return `
      <li class="karaoke-queue__item">
        <span class="karaoke-queue__position">${index + 1}</span>
        <img class="karaoke-queue__art" src="${this.escapeAttribute(item.image_url)}" alt="">
        <span class="karaoke-queue__meta">
          <strong>${this.escape(item.title)}</strong>
          <span>${this.escape(item.artist)}${by}</span>
        </span>
        ${state}
        <span class="karaoke-queue__actions">
          <button type="button" class="karaoke-queue__action" data-id="${item.id}"
                  data-action="karaoke-queue#playNow">Play</button>
          <button type="button" class="karaoke-queue__action" data-id="${item.id}"
                  data-action="karaoke-queue#promote" title="Move to the front" ${index === 0 ? "hidden" : ""}>↑</button>
          <button type="button" class="karaoke-queue__action" data-id="${item.id}"
                  data-action="karaoke-queue#remove" aria-label="Remove from queue">✕</button>
        </span>
      </li>
    `
  }

  flash(element, message) {
    const original = element.dataset.label || element.textContent
    element.dataset.label = original
    element.textContent = message
    setTimeout(() => { element.textContent = original }, 2000)
  }

  escape(value) {
    return String(value ?? "").replace(/[&<>]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[char]))
  }

  escapeAttribute(value) {
    return this.escape(value).replace(/"/g, "&quot;")
  }
}
