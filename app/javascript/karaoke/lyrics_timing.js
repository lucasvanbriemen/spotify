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
// Duet markers some lyric sources use to say who sings a line.
const SINGER_PREFIX_PATTERN = /^\s*(?:\[?(v1|v2|m|f|male|female|duet|both)\]?\s*[:.])\s*/i
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
// same line — the two parsers agree, but a mismatched pair would desync the
// whole song rather than one phrase.
const WORD_MERGE_TOLERANCE_SECONDS = 0.05

function timestampSeconds(match) {
  const fraction = match[3] ? parseInt(match[3], 10) / 10 ** match[3].length : 0
  return parseInt(match[1], 10) * 60 + parseInt(match[2], 10) + fraction
}

function singerOf(text) {
  const match = text.match(SINGER_PREFIX_PATTERN)
  if (!match) return { text, singer: null }

  const marker = match[1].toLowerCase()
  const singer = marker === "v1" || marker === "m" || marker === "male" ? 1
    : marker === "v2" || marker === "f" || marker === "female" ? 2
      : null

  return { text: text.slice(match[0].length), singer }
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
  }

  static empty() {
    return new LyricsTimeline([])
  }

  // wordsPayload is words.json, or null.
  static parse(source, wordsPayload = null) {
    const entries = parseLrc(source || "")
    if (entries.length === 0) return LyricsTimeline.empty()

    const payloadLines = wordsPayload?.lines || null

    const lines = entries.map((entry, index) => {
      const time = entry.time
      const nextTime = index + 1 < entries.length ? entries[index + 1].time : time + LAST_LINE_FALLBACK_SECONDS
      const stripped = entry.raw.replace(WORD_TAG_PATTERN, " ").replace(/\s+/g, " ").trim()
      const { text, singer } = singerOf(stripped)

      let endTime = nextTime
      let words = null

      const fromPayload = payloadLines?.[index]
      if (fromPayload && Math.abs(fromPayload.start - time) <= WORD_MERGE_TOLERANCE_SECONDS) {
        words = fromPayload.words.map((word) => ({ text: word.w, start: word.start, end: word.end }))
        endTime = fromPayload.end
      }

      if (!words) {
        const inline = enhancedWords(entry.raw, nextTime)
        if (inline) {
          words = inline.map((word) => {
            const cleaned = singerOf(word.text)
            return { ...word, text: cleaned.text || word.text }
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

      return { time, endTime: Math.max(endTime, time + 0.05), text, singer, ...withCharOffsets(words) }
    })

    return new LyricsTimeline(lines)
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
