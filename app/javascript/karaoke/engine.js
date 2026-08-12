// The stage's single requestAnimationFrame loop.
//
// Everything that has to stay in step with the music is driven from here:
// which lyric line is active and how far the highlight has swept across it,
// when to count the singer in, and what each singer's voice is worth against
// the song's notes.
//
// The old implementation hung all of this off the audio element's timeupdate
// event, which browsers fire about four times a second — so the highlight
// stepped in quarter-second jumps and most of the mic's pitch estimates were
// thrown away between ticks. Reading the transport's clock once per frame
// fixes both.
import { LyricsTimeline } from "karaoke/lyrics_timing"
import { Melody } from "karaoke/melody"
import { SingerScore } from "karaoke/scoring"
import { GuideMelody } from "karaoke/guide_melody"
import { PitchSmoother } from "karaoke/pitch_smoother"

// How long the count-in runs, and how much silence has to precede a line
// before the singer needs one.
const COUNT_IN_SECONDS = 3
const GAP_CUE_SECONDS = 2
// The beat after "1": the count-in holds a terminal "GO" state this long into
// the line, so it can play an exit instead of vanishing on the exact frame the
// first word starts. Signalled as digit 0.
const GO_SECONDS = 0.7
// A note held longer than this is worth telling the singer to hold.
const HELD_SECONDS = 0.7

export class KaraokeEngine extends EventTarget {
  constructor({ transport, settings, view = null }) {
    super()
    this.transport = transport
    this.settings = settings
    this.view = view

    this.timeline = LyricsTimeline.empty()
    this.melody = Melody.empty()
    this.mics = []
    this.singers = []
    this.scores = []
    this.smoothers = []
    this.micListeners = []
    this.frameHandle = null
    // How far the instrumental file runs behind the timeline the lyrics and
    // notes were made against — non-zero when a YouTube upload with a longer
    // lead-in replaced the demucs instrumental (see VocalSeparation#aligned?).
    this.alignmentOffset = 0
    this.guide = new GuideMelody(transport.context, transport.output)

    // Anything scheduled ahead of a seek or a pause describes a moment that is
    // no longer about to happen.
    for (const event of [ "seeked", "pause", "play" ]) {
      transport.addEventListener(event, () => this.guide.reset())
    }
    transport.addEventListener("seeked", (event) => {
      this.scores.forEach((score) => score.rewindTo(event.detail.time))
    })

    // Reused every frame: the view reads it and returns, so there is no need
    // to allocate a fresh object sixty times a second.
    this.frameState = {
      time: 0,
      duration: 0,
      line: { index: -1, sweep: 0, wordIndex: -1, next: -1 },
      held: false,
      countIn: null,
      singers: []
    }
    this.countInState = { kind: "initial", secondsRemaining: 0, digit: 3 }
  }

  loadSong({ timeline, melody, singers = [] }) {
    this.timeline = timeline || LyricsTimeline.empty()
    this.melody = melody || Melody.empty()
    this.singers = singers
    this.scores = singers.map((singer) => new SingerScore(this.melody, singer))
    this.smoothers = singers.map(() => new PitchSmoother())
    this.frameState.singers = singers.map(() => ({ midi: null, voiced: false, level: 0, score: 0, combo: 0 }))

    this.guide.setMelody(this.melody)
    this.guide.setTranspose(this.#guideTranspose(singers))
    this.view?.setLines?.(this.timeline.lines)
    this.view?.setNotes?.(this.melody, this.scores)
  }

  // The song's timing data (lyrics, words, notes) describes the original
  // recording; a YouTube instrumental can run a fraction of a second behind
  // it. Applied to the display clock and the scoring clock alike, so both
  // follow what is actually heard.
  setAlignmentOffset(seconds) {
    this.alignmentOffset = Number.isFinite(seconds) ? seconds : 0
  }

  // Scoring is octave-invariant, but the guide tone is audible: play it in
  // the singer's own register, shifted by whole octaves towards wherever the
  // mic check heard them sing.
  #guideTranspose(singers) {
    const register = singers.map((singer) => singer.registerMidi).find((midi) => Number.isFinite(midi))
    const median = this.melody.medianMidi
    if (!Number.isFinite(register) || !Number.isFinite(median)) return 0

    const octaves = Math.round((register - median) / 12)
    return Math.max(-2, Math.min(2, octaves)) * 12
  }

  setMics(mics) {
    // Listeners are torn down first: mics outlive a song, so re-attaching on
    // every performance would stack a new handler on the same MicInput each
    // time.
    this.#releaseMicListeners()
    this.mics = mics || []
    this.micListeners = this.mics.map((mic, index) => {
      if (!mic) return null

      const handler = () => this.scores[index]?.markMicLost(this.transport.currentTime)
      mic.addEventListener("ended", handler)
      return { mic, handler }
    })
  }

  // Wipes every singer's accumulated notes, lines and combo so the same song
  // can be sung again from a clean slate.
  resetScores() {
    this.scores.forEach((score) => score.reset())
    this.frameState.singers.forEach((singer) => { singer.score = 0; singer.combo = 0 })
    this.view?.setNotes?.(this.melody, this.scores)
  }

  #releaseMicListeners() {
    this.micListeners?.forEach((entry) => entry?.mic.removeEventListener("ended", entry.handler))
    this.micListeners = []
  }

  get hasScoring() {
    return this.scores.length > 0 && !this.melody.isEmpty
  }

  start() {
    if (this.frameHandle !== null) return

    const tick = () => {
      this.frameHandle = requestAnimationFrame(tick)
      this.#frame()
    }
    this.frameHandle = requestAnimationFrame(tick)
  }

  stop() {
    if (this.frameHandle === null) return

    cancelAnimationFrame(this.frameHandle)
    this.frameHandle = null
  }

  setGuideMelody(enabled) {
    this.guide.setEnabled(enabled)
  }

  destroy() {
    this.stop()
    this.guide.destroy()
    this.#releaseMicListeners()
    this.view = null
    this.mics = []
  }

  // Everything the results screen needs. Safe to call more than once.
  results() {
    return this.scores.map((score) => score.results(this.timeline))
  }

  #frame() {
    // The transport clock is the scheduling clock; sound reaches the room a
    // little later. Drawing on the scheduling clock makes every word light up
    // before it is heard, which reads as the whole stage running early.
    const time = this.transport.currentTime - this.alignmentOffset
      - this.settings.displayOffsetSeconds(this.transport.context)
    const state = this.timeline.stateAt(time)
    const frame = this.frameState

    frame.time = time
    frame.duration = this.transport.duration
    frame.line.index = state.index
    frame.line.sweep = state.sweep
    frame.line.wordIndex = state.wordIndex
    frame.line.next = state.next
    frame.held = this.#isHeld(time, state)
    frame.countIn = this.#countIn(time, state)

    const offset = this.mics.length > 0 ? this.settings.scoringOffsetSeconds(this.transport.context) : 0
    this.#drainMics(offset)
    this.#advanceScoring(time - offset)
    this.guide.schedule(time, (songTime) => this.transport.contextTimeFor(songTime + this.alignmentOffset))

    this.view?.frame?.(frame)
  }

  // Prefer the melody: a real note tells us how long it is held, where the
  // word timing is only ever an estimate.
  #isHeld(time, state) {
    if (!this.melody.isEmpty) {
      const [ note ] = this.melody.notesInWindow(time, time)
      return Boolean(note) && note.duration >= HELD_SECONDS
    }

    if (!state.line || state.wordIndex < 0) return false

    const word = state.line.words[state.wordIndex]
    return Boolean(word) && word.end - word.start >= HELD_SECONDS
  }

  // A pure function of the clock, so seeking backwards into an intro re-arms
  // the count-in without any state to reset.
  #countIn(time, state) {
    // Just past a counted-in line's start: hold a "GO" beat (digit 0) so the
    // view can play an exit animation over the first word.
    const current = state.index >= 0 ? this.timeline.lines[state.index] : null
    if (current && time - current.time < GO_SECONDS && this.#countedIn(state.index)) {
      this.countInState.kind = state.index === 0 ? "initial" : "gap"
      this.countInState.secondsRemaining = 0
      this.countInState.digit = 0
      return this.countInState
    }

    const upcoming = state.index < 0 ? 0 : state.next
    const line = this.timeline.lines[upcoming]
    if (!line) return null

    const gap = this.timeline.gapBefore(upcoming)
    if (gap < (state.index < 0 ? 0 : GAP_CUE_SECONDS)) return null

    const remaining = line.time - time
    if (remaining <= 0 || remaining > COUNT_IN_SECONDS) return null

    this.countInState.kind = state.index < 0 ? "initial" : "gap"
    this.countInState.secondsRemaining = remaining
    this.countInState.digit = Math.max(1, Math.ceil(remaining))
    return this.countInState
  }

  // Whether a line was preceded by a count-in, mirroring the gate above: the
  // first line always is (the pre-roll makes room), later ones only after a
  // real instrumental break.
  #countedIn(index) {
    return index === 0 || this.timeline.gapBefore(index) >= GAP_CUE_SECONDS
  }

  // Mic frames carry the context time they were measured at, so a stalled
  // main thread delays when they are scored, never what they are scored
  // against.
  #drainMics(offset) {
    if (this.mics.length === 0) return

    this.mics.forEach((mic, index) => {
      if (!mic) return

      const singer = this.frameState.singers[index]
      const score = this.scores[index]
      const smoother = this.smoothers[index]
      const frames = mic.drainFrames()
      let drawn

      for (const sample of frames) {
        const fileTime = this.transport.songTimeAt(sample.t)
        if (fileTime === null) continue
        const songTime = fileTime - this.alignmentOffset

        const at = songTime - offset
        // Scoring gets the raw estimate: smoothing would only make it late.
        if (at >= 0) score?.addFrame(at, sample.hz)

        const midi = sample.hz ? 69 + 12 * Math.log2(sample.hz / 440) : null
        drawn = smoother?.push(midi, songTime) ?? midi
      }

      if (singer) {
        if (frames.length > 0) {
          singer.midi = drawn ?? null
          singer.voiced = drawn !== null && drawn !== undefined
        }
        singer.level = mic.level
      }
    })
  }

  #advanceScoring(scoringTime) {
    if (!this.hasScoring) return

    this.scores.forEach((score, index) => {
      for (const verdict of score.advance(scoringTime)) {
        this.view?.lineVerdict?.(index, verdict.verdict)
      }

      const singer = this.frameState.singers[index]
      if (singer) {
        singer.score = score.score
        singer.combo = score.combo
      }
    })
  }
}
