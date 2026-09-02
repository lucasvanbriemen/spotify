// Turns LRCLIB's synced lyrics into a timeline the stage can sweep a
// highlight across.
//
// Word timings come from the best source available, in order:
//   1. words.json, derived server-side from where the vocal stem is actually
//      voiced (see script/karaoke_separate.py)
//   2. Enhanced-LRC <mm:ss.xx> tags, when the lyrics happen to carry them
//   3. an estimate weighted by word length, which is all the original
//      line-timed LRC supports
//
// Only the first two are real; the third is a guess that looks approximately
// right and is what the feature shipped with.

const TIMESTAMP_PATTERN = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g
const WORD_TAG_PATTERN = /<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>/g

// --- Who sings which line -------------------------------------------------
//
// Lyric sources say it in three different ways, and all three are read here,
// because a song that can be split is a song two people on one microphone get
// a score each on (see the engine's #ownershipFor).
//
//   1. a part marker      "v1: ...", "F: ...", "[Both] ..."
//   2. a name             "Rihanna: ...", "[Eminem] ..."
//   3. a section header   "[Verse 1: Beyoncé]" over the lines that follow it
//
// Names carry no part number of their own, so they are numbered by where they
// first appear — and only honoured when the song looks like a real dialogue
// (two or three of them, each on more than one line). One "Baby: hold on"
// inside a lyric is not a duet, and reading it as one would strip a word out
// of the line and hand half the song to the wrong singer.
const PART_MARKER_PATTERN = /^\s*\[?\s*(v1|v2|p1|p2|m|f|male|female|duet|both|all|together|everyone)\s*\]?\s*[:.]\s*/i
// A bracketed name ("[Eminem]") or a bare one ("Rihanna:"). Bare names must be
// followed by a space, so "Baby:tonight" and timestamps never qualify.
const NAME_MARKER_PATTERN = /^\s*(?:\[\s*([^[\]:]{1,28}?)\s*\]\s*|([\p{L}][\p{L}\p{M}\d .'&-]{0,27}?)\s*:\s+)/u
// "[Verse 1: Beyoncé]", "[Chorus: Both]" — a whole line that only labels the
// section, naming who takes the lines under it.
const SECTION_HEADER_PATTERN = /^\[\s*[^[\]]*?:\s*([^[\]]+?)\s*\]$/
const PART_ONE_MARKERS = new Set([ "v1", "p1", "m", "male" ])
const PART_TWO_MARKERS = new Set([ "v2", "p2", "f", "female" ])
// Words that name everybody rather than one singer. A line marked with one of
// these belongs to both parts, exactly like an unmarked line — but it is
// *marked*, which is what stops the one-sided fill below from claiming it.
const EVERYONE_MARKERS = new Set([ "duet", "both", "all", "together", "everyone" ])
// What a bracketed label is when it isn't a person. LRC files are full of
// "[Chorus]" and "[Verse 2]", and reading two of those as two singers would
// hand the chorus to one of them and the verses to the other.
const SECTION_WORDS = new Set([
  "verse", "chorus", "prechorus", "pre chorus", "bridge", "intro", "outro", "refrain",
  "hook", "interlude", "instrumental", "break", "breakdown", "solo", "coda", "spoken", "rap"
])

// "Verse 2" and "Verse" are the same label; a singer's name is not numbered.
function isSectionWord(key) {
  return SECTION_WORDS.has(key.replace(/[\s-]*\d+\s*$/, "").replace(/-/g, " ").trim())
}
// A name has to turn up on at least this many lines before it is read as a
// singer rather than as a word that happens to end in a colon.
const MIN_LINES_PER_NAME = 2
// How much silence ends a section, for the structural split. Line ends are
// mostly estimates, and a slow song leaves seconds between two lines of the
// same breath, so this is well past what a pause inside a verse looks like.
const SECTION_GAP_SECONDS = 4
// And a verse is several lines, not one. Anything shorter is folded into the
// section before it — without this, a ballad's every line becomes its own
// section and the two singers ping-pong line by line, which is not how a room
// splits a song. (Bohemian Rhapsody, measured: 50 lines, 40-odd sections.)
const MIN_LINES_PER_SECTION = 3
// Fewer sections than this is not a structure worth alternating across — it is
// one verse and a chorus, and guessing who takes what would be a coin flip.
const MIN_SECTIONS = 4
const MIN_LINES_PER_STRUCTURAL_PART = 2

// A few songs are call-and-response duets — the two singers trade a line each,
// all the way through — and their lyrics say nothing about it. Structure alone
// cannot find that: it groups lines by the musical breaks between them, so it
// hands out whole verses, which is right for most duets and wrong for these.
// Alternating line by line on every unmarked song would be wrong far more
// often than right, so the ones that work that way are named here.
//
// Matched on artist and title rather than ISRC: the same recording turns up
// under a different ISRC on every remaster and compilation.
const LINE_BY_LINE_DUETS = [
  { title: /don'?t go breaking my heart/i, artist: /elton john|kiki dee/i }
]

function isLineByLineDuet(track) {
  if (!track) return false

  return LINE_BY_LINE_DUETS.some(({ title, artist }) =>
    title.test(track.title || "") && artist.test(track.artist || ""))
}
// How long a line of a given length plausibly takes to sing. Used only when
// nothing better is available: without it a line would be assumed to run right
// up to the next one, so the highlight would crawl through an instrumental
// break and no gap would ever be long enough to count the singer back in.
// Deliberately generous — a sweep that finishes early looks worse than one
// that finishes late, and during continuous singing the next line's timestamp
// caps it anyway.
const SECONDS_PER_CHARACTER = 0.11
const MIN_LINE_SECONDS = 0.6
// LRCLIB gives no end for the final line; long enough to finish a phrase.
const LAST_LINE_FALLBACK_SECONDS = 4
// A words.json line has to start where the LRC line does to be trusted as the
// same line — the two parsers agree on timestamps, so a real pair matches
// almost exactly and anything further off is a different line.
const WORD_MERGE_TOLERANCE_SECONDS = 0.05

function timestampSeconds(match) {
  const fraction = match[3] ? parseInt(match[3], 10) / 10 ** match[3].length : 0
  return parseInt(match[1], 10) * 60 + parseInt(match[2], 10) + fraction
}

// One line's marker, before the song as a whole has decided what the names in
// it mean: { prefix, key, kind }, or null when the line names nobody.
function markerIn(text) {
  const part = text.match(PART_MARKER_PATTERN)
  if (part) return { prefix: part[0], key: part[1].toLowerCase(), kind: "part" }

  const header = text.match(SECTION_HEADER_PATTERN)
  if (header) return { prefix: text, key: header[1].toLowerCase().trim(), kind: "header" }

  const name = text.match(NAME_MARKER_PATTERN)
  if (name) return { prefix: name[0], key: (name[1] || name[2]).toLowerCase().trim(), kind: "name" }

  return null
}

function partOfMarker(key) {
  if (PART_ONE_MARKERS.has(key)) return 1
  if (PART_TWO_MARKERS.has(key)) return 2
  return null
}

// Names get their part number from where they first appear, so the song has to
// be read as a whole before any one line can be resolved. Returns a
// key -> 1 | 2 | null map, or null when the names don't look like a dialogue
// (see MIN_LINES_PER_NAME) and should be left alone as ordinary text.
function numberNames(markers) {
  const counts = new Map()
  for (const marker of markers) {
    if (!marker || marker.kind === "part") continue
    if (EVERYONE_MARKERS.has(marker.key)) continue
    if (partOfMarker(marker.key) !== null) continue
    if (isSectionWord(marker.key)) continue

    counts.set(marker.key, (counts.get(marker.key) || 0) + 1)
  }

  // A section header names its singer once and speaks for every line under it,
  // so it is never held to the repeat count a bare "Name:" prefix is.
  const headers = new Set(markers.filter((marker) => marker?.kind === "header").map((marker) => marker.key))
  const named = [ ...counts.keys() ].filter((key) => headers.has(key) || counts.get(key) >= MIN_LINES_PER_NAME)
  if (named.length < 2 || named.length > 3) return null

  const numbered = new Map()
  let next = 1
  for (const key of named) {
    // A third name is all but always "the two of them at once".
    numbered.set(key, next <= 2 ? next : null)
    next += 1
  }
  return numbered
}

// Resolves every line at once: [{ text, singer, marked }], with the marker
// stripped from text wherever it was honoured. singer is 1, 2 or null; marked
// says the line named *somebody*, which is how an explicit "both:" is told
// apart from a line that simply says nothing.
function assignSingers(texts) {
  const markers = texts.map(markerIn)
  const names = numberNames(markers)
  let section = null

  return texts.map((text, index) => {
    const marker = markers[index]

    if (marker?.kind === "header") {
      // The header line itself is a label, not a lyric: it carries no part of
      // its own, and what it names applies from here to the next header.
      section = names?.has(marker.key) ? names.get(marker.key)
        : EVERYONE_MARKERS.has(marker.key) ? null
          : partOfMarker(marker.key)
      return { text, singer: null, marked: true }
    }

    if (marker?.kind === "part") {
      return { text: text.slice(marker.prefix.length), singer: partOfMarker(marker.key), marked: true }
    }

    if (marker?.kind === "name") {
      // A bracketed marker without a colon ("[Both]", "[V2]") says the same
      // thing a "both:" prefix does, and is stripped just as readily.
      const named = EVERYONE_MARKERS.has(marker.key) ? { singer: null }
        : partOfMarker(marker.key) !== null ? { singer: partOfMarker(marker.key) }
          : names?.has(marker.key) ? { singer: names.get(marker.key) } : null

      if (named) return { text: text.slice(marker.prefix.length), singer: named.singer, marked: true }
    }

    // Under a section header, and saying nothing to the contrary.
    return { text, singer: section, marked: section !== null }
  })
}

// One part marked and the other left to inference: lyrics that only bracket
// the guest's lines ("(Rihanna)") are describing a duet just as plainly as
// ones that mark both, so the lines nobody claimed go to the other singer.
// Explicit "both:" lines are marked, so they stay everybody's.
function fillOppositePart(lines) {
  const claimed = new Set(lines.map((line) => line.singer).filter(Boolean))
  if (claimed.size !== 1) return

  const other = claimed.has(1) ? 2 : 1
  const unclaimed = lines.filter((line) => line.singer === null && !line.marked)
  if (unclaimed.length < MIN_LINES_PER_STRUCTURAL_PART) return
  if (lines.length - unclaimed.length < MIN_LINES_PER_STRUCTURAL_PART) return

  for (const line of unclaimed) line.singer = other
}

// The last resort, for the songs — most of them — whose lyrics say nothing
// about who sings what: split the song by its own structure. Lines are grouped
// into sections at the instrumental gaps between them, the sections whose words
// repeat (the chorus) go to both singers, and the rest alternate.
//
// This is a guess, which is why it is not baked into the timeline: the
// coordinator applies it only when two people are actually sharing one
// microphone and the alternative is a single score between them.
function structuralParts(lines) {
  if (lines.some((line) => line.singer !== null || line.marked)) return null
  if (lines.length < MIN_SECTIONS * MIN_LINES_PER_STRUCTURAL_PART) return null

  const sections = []
  lines.forEach((line, index) => {
    const gap = index === 0 ? Infinity : line.time - lines[index - 1].endTime
    // A break only starts a new section once the one before it is a verse's
    // worth of lines; short ones are the pauses inside a verse, not between.
    const previous = sections[sections.length - 1]
    if (gap >= SECTION_GAP_SECONDS && (!previous || previous.indexes.length >= MIN_LINES_PER_SECTION)) {
      sections.push({ indexes: [], words: [] })
    }

    sections[sections.length - 1].indexes.push(index)
    sections[sections.length - 1].words.push(line.text)
  })

  // The last section can still come up short — it is nobody's "previous".
  if (sections.length > 1 && sections[sections.length - 1].indexes.length < MIN_LINES_PER_SECTION) {
    const tail = sections.pop()
    const last = sections[sections.length - 1]
    last.indexes.push(...tail.indexes)
    last.words.push(...tail.words)
  }

  if (sections.length < MIN_SECTIONS) return null

  const occurrences = new Map()
  for (const section of sections) {
    section.key = section.words.join(" ").toLowerCase().replace(/[^\p{L}\p{N} ]/gu, "").replace(/\s+/g, " ").trim()
    occurrences.set(section.key, (occurrences.get(section.key) || 0) + 1)
  }

  const parts = new Array(lines.length).fill(null)
  const assigned = [ 0, 0 ]
  let turn = 0

  for (const section of sections) {
    if (occurrences.get(section.key) > 1) continue // the chorus: everyone sings it

    const part = (turn % 2) + 1
    turn += 1
    assigned[part - 1] += section.indexes.length
    for (const index of section.indexes) parts[index] = part
  }

  return assigned.every((count) => count >= MIN_LINES_PER_STRUCTURAL_PART) ? parts : null
}

// Mirrors the server-side parser: a line's text is everything after its last
// timestamp, and one line can carry several timestamps (LRC compression), each
// producing an entry that shares the text.
function parseLrc(source) {
  const entries = []

  for (const rawLine of source.split("\n")) {
    const matches = [ ...rawLine.matchAll(TIMESTAMP_PATTERN) ]
    if (matches.length === 0) continue

    const last = matches[matches.length - 1]
    const content = rawLine.slice(last.index + last[0].length).trim()
    if (!content) continue

    for (const match of matches) entries.push({ time: timestampSeconds(match), raw: content })
  }

  return entries.sort((a, b) => a.time - b.time)
}

// Word tags inline in the text, e.g. "<00:12.30> Hello <00:12.80> from".
function enhancedWords(raw, lineEnd) {
  const matches = [ ...raw.matchAll(WORD_TAG_PATTERN) ]
  if (matches.length === 0) return null

  const words = []
  for (let index = 0; index < matches.length; index++) {
    const match = matches[index]
    const following = matches[index + 1]
    const text = raw.slice(match.index + match[0].length, following ? following.index : raw.length).trim()
    if (!text) continue

    const start = timestampSeconds(match)
    words.push({ text, start, end: following ? timestampSeconds(following) : lineEnd })
  }

  return words.length > 0 ? words : null
}

function estimatedLineEnd(text, start, nextStart) {
  const singing = Math.max(MIN_LINE_SECONDS, text.length * SECONDS_PER_CHARACTER)
  return Math.min(nextStart, start + singing)
}

// What the original feature did, kept as the last resort: give each word a
// share of the line proportional to its length.
function estimatedWords(text, start, end) {
  const tokens = text.split(/\s+/).filter(Boolean)
  if (tokens.length === 0) return []

  const weights = tokens.map((word) => word.length + 1)
  const total = weights.reduce((sum, weight) => sum + weight, 0)
  const span = Math.max(0, end - start)

  let cumulative = 0
  return tokens.map((word, index) => {
    const from = start + (span * cumulative) / total
    cumulative += weights[index]
    return { text: word, start: from, end: start + (span * cumulative) / total }
  })
}

// Server word timings are matched to LRC entries by START TIME, never by
// array index: the server skips lines it can't time (zero-width windows, no
// words), and an index pairing silently shifts every line after the first
// skip onto the wrong timings — the estimate fallback then takes over for the
// rest of the song. Both lists are sorted, so one forward cursor suffices;
// each payload line is claimed at most once (LRC compression can put two
// entries on one timestamp, and only one of them can own the words).
class PayloadLines {
  constructor(payload) {
    this.lines = [ ...(payload?.lines || []) ].sort((a, b) => a.start - b.start)
    this.cursor = 0
  }

  claim(time) {
    while (this.cursor < this.lines.length && this.lines[this.cursor].start < time - WORD_MERGE_TOLERANCE_SECONDS) {
      this.cursor++
    }

    const candidate = this.lines[this.cursor]
    if (!candidate || Math.abs(candidate.start - time) > WORD_MERGE_TOLERANCE_SECONDS) return null

    this.cursor++
    return candidate
  }
}

// Character offsets let the view sweep a highlight in proportion to how much
// of the line has been sung, rather than how much of its time has passed —
// which is what keeps the wipe under the word actually being sung.
function withCharOffsets(words) {
  let offset = 0
  const positioned = words.map((word) => {
    const charStart = offset
    offset += word.text.length
    const charEnd = offset
    offset += 1 // the space that follows
    return { ...word, charStart, charEnd }
  })

  return { words: positioned, charTotal: Math.max(1, offset - 1) }
}

export class LyricsTimeline {
  constructor(lines) {
    this.lines = lines
    this.cursor = 0
    this.plan = undefined
  }

  static empty() {
    return new LyricsTimeline([])
  }

  // wordsPayload is words.json, or null.
  static parse(source, wordsPayload = null) {
    const entries = parseLrc(source || "")
    if (entries.length === 0) return LyricsTimeline.empty()

    const payloadLines = new PayloadLines(wordsPayload)
    // Who sings what is decided for the whole song at once: a name only earns
    // a part number from how often, and where, it turns up across every line.
    const stripped = entries.map((entry) => entry.raw.replace(WORD_TAG_PATTERN, " ").replace(/\s+/g, " ").trim())
    const assigned = assignSingers(stripped)

    const lines = entries.map((entry, index) => {
      const time = entry.time
      const nextTime = index + 1 < entries.length ? entries[index + 1].time : time + LAST_LINE_FALLBACK_SECONDS
      const { text, singer, marked } = assigned[index]

      let endTime = nextTime
      let words = null

      const fromPayload = payloadLines.claim(time)
      if (fromPayload) {
        words = fromPayload.words.map((word) => ({ text: word.w, start: word.start, end: word.end }))
        // The displayed text drops the duet marker; timings that still carry
        // it as a word would count its characters into the sweep and skew the
        // wipe across the whole line.
        if (text !== stripped[index]) {
          const prefixTokens = stripped[index].slice(0, stripped[index].length - text.length).trim().split(/\s+/).filter(Boolean)
          for (const token of prefixTokens) {
            if (words[0]?.text === token) words.shift()
          }
        }
        endTime = fromPayload.end
        if (words.length === 0) words = null // nothing left to sweep; estimate instead
      }

      if (!words) {
        const inline = enhancedWords(entry.raw, nextTime)
        if (inline) {
          words = inline.map((word) => {
            // Only a part marker: a bare "Name:" is stripped from the line's
            // text but never from a word, where it could be a real lyric.
            const marker = markerIn(word.text)
            const cleaned = marker?.kind === "part" ? word.text.slice(marker.prefix.length) : word.text
            return { ...word, text: cleaned || word.text }
          })
          endTime = words[words.length - 1].end
        }
      }

      if (!words) {
        endTime = estimatedLineEnd(text, time, nextTime)
        words = estimatedWords(text, time, endTime)
      }

      // A word list from a mismatched source could still be empty; the line
      // must always have something to render.
      if (words.length === 0) words = estimatedWords(text || " ", time, endTime)

      return { time, endTime: Math.max(endTime, time + 0.05), text, singer, marked, ...withCharOffsets(words) }
    })

    fillOppositePart(lines)

    return new LyricsTimeline(lines)
  }

  // Whether two singers can be scored separately on this song — because the
  // lyrics say who sings what, because it is a known call-and-response duet,
  // or because its structure is clear enough to alternate across.
  splittableFor(track = null) {
    return isLineByLineDuet(track) || this.splittable
  }

  get splittable() {
    return this.hasBothParts || this.#structuralPlan() !== null
  }

  get hasBothParts() {
    return [ 1, 2 ].every((part) => this.lines.some((line) => line.singer === part))
  }

  // Writes a split onto the lines, so the stage colours them and the engine
  // scores them per singer. A no-op on a song the lyrics already split.
  // Returns whether the song ended up split at all.
  applySplit(track = null) {
    if (this.hasBothParts) return true

    // A named call-and-response duet trades a line each the whole way through.
    if (isLineByLineDuet(track)) {
      this.lines.forEach((line, index) => { line.singer = (index % 2) + 1 })
      return true
    }

    const plan = this.#structuralPlan()
    if (!plan) return false

    plan.forEach((part, index) => { this.lines[index].singer = part })
    return true
  }

  // Computed once: it walks every line, and both the setup screen's notice and
  // the hand-off into the stage ask for it.
  #structuralPlan() {
    if (this.plan === undefined) this.plan = structuralParts(this.lines)
    return this.plan
  }

  get length() {
    return this.lines.length
  }

  get isEmpty() {
    return this.lines.length === 0
  }

  get firstStart() {
    return this.lines[0]?.time ?? null
  }

  // Silence before a line, used to decide whether the singer needs counting in.
  gapBefore(index) {
    if (index <= 0) return this.lines[0] ? this.lines[0].time : 0

    return this.lines[index].time - this.lines[index - 1].endTime
  }

  // The last line whose timestamp has passed, plus how far through it we are.
  // Walks from the previous answer rather than searching, since time almost
  // always moves forward by one frame.
  stateAt(time) {
    const lines = this.lines
    if (lines.length === 0) return { index: -1, sweep: 0, wordIndex: -1, next: -1, line: null }

    let index = Math.min(this.cursor, lines.length - 1)
    if (lines[index].time > time) index = -1
    while (index + 1 < lines.length && lines[index + 1].time <= time) index += 1
    this.cursor = Math.max(0, index)

    if (index < 0) {
      return { index: -1, sweep: 0, wordIndex: -1, next: 0, line: null }
    }

    const line = lines[index]
    const { sweep, wordIndex } = this.#sweepWithin(line, time)

    return { index, sweep, wordIndex, next: index + 1 < lines.length ? index + 1 : -1, line }
  }

  #sweepWithin(line, time) {
    const words = line.words
    if (time >= line.endTime) return { sweep: 1, wordIndex: words.length - 1 }

    for (let index = 0; index < words.length; index++) {
      const word = words[index]
      if (time >= word.end) continue

      if (time < word.start) {
        // In the gap before this word: the highlight waits at its start rather
        // than creeping across silence.
        return { sweep: word.charStart / line.charTotal, wordIndex: index }
      }

      const span = Math.max(1e-6, word.end - word.start)
      const within = Math.max(0, Math.min(1, (time - word.start) / span))
      const chars = word.charStart + within * (word.charEnd - word.charStart)
      return { sweep: Math.max(0, Math.min(1, chars / line.charTotal)), wordIndex: index }
    }

    return { sweep: 1, wordIndex: words.length - 1 }
  }
}
