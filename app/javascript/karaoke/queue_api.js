// The queue endpoints, shared by the karaoke screen and the phone remote.
//
// Both talk to the same rows. Nothing is passed for authorisation: the screen
// is a logged-in page, and the remote's requests carry the join-code cookie
// /karaoke/remote set when it was unlocked.
//
// Every call resolves to a payload with an `ok` flag rather than throwing or
// resolving to null — a queue that quietly stops working is worse than one
// that says it couldn't add the song, and both callers want to tell the
// difference between "full" and "offline".
const BASE = "/api/karaoke/queue"
const JSON_HEADERS = { "Content-Type": "application/json" }

async function request(url, options = {}) {
  let response

  try {
    response = await fetch(url, options)
  } catch {
    return { ok: false, offline: true }
  }

  const payload = await response.json().catch(() => ({}))
  return { ok: response.ok, ...payload }
}

export const QueueApi = {
  // -> { ok, now_playing, items: [ { id, isrc, title, artist, image_url,
  //      added_by, status, ready } ] }
  list() {
    return request(BASE)
  },

  add(song, addedBy) {
    return request(BASE, {
      method: "POST",
      headers: JSON_HEADERS,
      body: JSON.stringify({
        isrc: song.isrc,
        title: song.title,
        artist: song.artist,
        image_url: song.image_url,
        added_by: addedBy
      })
    })
  },

  remove(id) {
    return request(`${BASE}/${id}`, { method: "DELETE" })
  },

  promote(id) {
    return request(`${BASE}/${id}/promote`, { method: "POST" })
  },

  // One place up or down. "up" and "down" rather than a target index: the list
  // is re-rendered from a poll, so an index a phone computed a moment ago may
  // already mean a different row.
  move(id, direction) {
    return request(`${BASE}/${id}/move`, {
      method: "POST",
      headers: JSON_HEADERS,
      body: JSON.stringify({ direction })
    })
  },

  // "playing" when the screen puts a song on stage, "done" when it comes off.
  setStatus(id, status) {
    return request(`${BASE}/${id}`, { method: "PATCH", headers: JSON_HEADERS, body: JSON.stringify({ status }) })
  },

  // Reorders the whole waiting list at random, server-side: the order has to
  // be the same one every phone in the room is looking at, so it cannot be
  // dealt out by whichever client happened to press the button.
  shuffle() {
    return request(`${BASE}/shuffle`, { method: "POST" })
  },

  clear() {
    return request(BASE, { method: "DELETE" })
  },

  search(query) {
    return request(`${BASE}/search?q=${encodeURIComponent(query)}`)
  }
}
