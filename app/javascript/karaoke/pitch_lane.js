// The pitch lane: the song's melody as bars on a scrolling piano roll, with
// each singer's live pitch drawn over them. This is the view that makes a
// karaoke screen a karaoke game rather than a lyrics player — you can see the
// note coming, see where you are, and see whether you're on it.
//
// Everything is drawn on one canvas. Note rectangles are recomputed only when
// the lane resizes, the visible window is found by binary search, and nothing
// per-frame touches the DOM.

// How much of the song is on screen either side of now.
const SECONDS_BEHIND = 2
const SECONDS_AHEAD = 5
// The now-line sits left of centre so there's more lead-in than run-out.
const NOW_POSITION = 0.28
const NOTE_HEIGHT_RATIO = 0.55
const TRAIL_SECONDS = 1.2
const MIN_NOTE_WIDTH = 3
// A note counts as sung once it is at least this close.
const HIT_THRESHOLD = 0.5

export class PitchLane {
  constructor(canvas, box) {
    this.canvas = canvas
    this.box = box
    this.context = canvas.getContext("2d")
    this.melody = null
    this.width = 0
    this.height = 0
    this.colors = { singers: [ "#22d3ee", "#a78bfa" ], gold: "#fcd34d", base: "rgba(244,244,248,0.28)" }
    this.scores = []
    // One ring buffer of recent pitch per singer, for the trailing line.
    this.trails = [ [], [] ]

    this.observer = new ResizeObserver(() => this.resize())
    this.observer.observe(box)
    this.resize()
  }

  setMelody(melody) {
    this.melody = melody && !melody.isEmpty ? melody : null
    this.trails = [ [], [] ]
  }

  // The per-singer scorers, read only for drawing: a note the singer landed is
  // filled in their colour, which is what makes the lane respond to singing
  // rather than just scroll past.
  setScores(scores) {
    this.scores = scores || []
  }

  setColors({ singers, gold }) {
    if (singers) this.colors.singers = singers
    if (gold) this.colors.gold = gold
  }

  resize() {
    const ratio = window.devicePixelRatio || 1
    const { width, height } = this.box.getBoundingClientRect()
    if (width === 0 || height === 0) return

    this.width = width
    this.height = height
    this.canvas.width = Math.round(width * ratio)
    this.canvas.height = Math.round(height * ratio)
    this.context.setTransform(ratio, 0, 0, ratio, 0, 0)
  }

  // midi -> y, with the lane's range mapped onto its height.
  yFor(midi) {
    const melody = this.melody
    const span = Math.max(1, melody.midiMax - melody.midiMin)
    const fraction = (midi - melody.midiMin) / span
    const usable = this.height * 0.86
    return this.height - (this.height * 0.07 + fraction * usable)
  }

  xFor(time, now) {
    const span = SECONDS_BEHIND + SECONDS_AHEAD
    return ((time - now + SECONDS_BEHIND) / span) * this.width
  }

  frame(now, singers) {
    const context = this.context
    if (!context || this.width === 0) return

    context.clearRect(0, 0, this.width, this.height)
    if (!this.melody) return

    const noteHeight = Math.max(6, (this.height / Math.max(6, this.melody.midiMax - this.melody.midiMin)) * NOTE_HEIGHT_RATIO)

    this.drawNowLine()
    this.drawNotes(now, noteHeight)
    this.drawSingers(now, singers, noteHeight)
  }

  drawNowLine() {
    const context = this.context
    const x = this.width * NOW_POSITION

    context.save()
    context.strokeStyle = "rgba(244,244,248,0.25)"
    context.lineWidth = 2
    context.beginPath()
    context.moveTo(x, 0)
    context.lineTo(x, this.height)
    context.stroke()
    context.restore()
  }

  drawNotes(now, noteHeight) {
    const context = this.context
    const visible = this.melody.notesInWindow(now - SECONDS_BEHIND, now + SECONDS_AHEAD)
    const radius = noteHeight / 2

    for (const note of visible) {
      const x = this.xFor(note.start, now)
      const width = Math.max(MIN_NOTE_WIDTH, this.xFor(note.end, now) - x)
      const y = this.yFor(note.midi) - noteHeight / 2

      // Notes already behind the now-line are dimmed, so the eye is drawn to
      // what's coming rather than what's gone.
      const passed = note.end < now
      context.globalAlpha = passed ? 0.35 : 1

      if (note.golden) {
        // A larger translucent rectangle stands in for a glow: shadowBlur is a
        // full gaussian per draw and far too expensive at 60fps.
        context.fillStyle = "rgba(252, 211, 77, 0.22)"
        this.roundedRect(x - 4, y - 4, width + 8, noteHeight + 8, radius + 4)
        context.fill()
        context.fillStyle = this.colors.gold
      } else {
        context.fillStyle = this.colors.base
      }

      this.roundedRect(x, y, width, noteHeight, radius)
      context.fill()

      this.drawHits(note, x, y, width, noteHeight, radius)
    }

    context.globalAlpha = 1
  }

  // Two singers share a note's bar, stacked, so neither hides the other.
  drawHits(note, x, y, width, height, radius) {
    const context = this.context
    const singers = this.scores.length

    this.scores.forEach((score, index) => {
      const accumulator = score?.notes?.[note.index]
      if (!accumulator || accumulator.frames === 0) return

      const accuracy = accumulator.credit / accumulator.frames
      if (accuracy < HIT_THRESHOLD) return

      const bandHeight = height / singers
      const bandY = y + bandHeight * index

      context.fillStyle = this.colors.singers[index] || this.colors.singers[0]
      this.roundedRect(x, bandY, width * Math.min(1, accuracy), bandHeight, Math.min(radius, bandHeight / 2))
      context.fill()
    })
  }

  drawSingers(now, singers, noteHeight) {
    const context = this.context

    singers?.forEach((singer, index) => {
      const trail = this.trails[index]
      if (!trail) return

      if (singer.voiced && Number.isFinite(singer.midi)) {
        const previous = trail.length > 0 ? trail[trail.length - 1].midi : null
        trail.push({ time: now, midi: this.foldToLane(singer.midi, previous) })
      } else if (trail.length > 0 && trail[trail.length - 1].midi !== null) {
        trail.push({ time: now, midi: null }) // break the line while they're silent
      }

      while (trail.length > 0 && trail[0].time < now - TRAIL_SECONDS) trail.shift()

      const color = this.colors.singers[index] || this.colors.singers[0]
      context.strokeStyle = color
      context.lineWidth = 3
      context.lineJoin = "round"
      context.lineCap = "round"
      context.globalAlpha = 0.85

      // Curves through the midpoints between samples: a polyline of 60-odd
      // points per second shows every corner, which reads as jitter even once
      // the values themselves are smooth.
      context.beginPath()
      let previous = null
      for (const point of trail) {
        if (point.midi === null) { previous = null; continue }

        const x = this.xFor(point.time, now)
        const y = this.yFor(point.midi)

        if (!previous) {
          context.moveTo(x, y)
        } else {
          context.quadraticCurveTo(previous.x, previous.y, (previous.x + x) / 2, (previous.y + y) / 2)
        }
        previous = { x, y }
      }
      if (previous) context.lineTo(previous.x, previous.y)
      context.stroke()

      const latest = trail[trail.length - 1]
      if (latest && latest.midi !== null) {
        context.globalAlpha = 1
        context.fillStyle = color
        context.beginPath()
        context.arc(this.xFor(latest.time, now), this.yFor(latest.midi), Math.max(5, noteHeight * 0.35), 0, Math.PI * 2)
        context.fill()
      }
    })

    context.globalAlpha = 1
  }

  // A singer an octave below the original still belongs on the same line as
  // the note they're matching — that's how they're scored, so that's how they
  // are drawn.
  foldToLane(midi, previous = null) {
    const { midiMin, midiMax } = this.melody
    let folded = midi
    while (folded < midiMin && folded + 12 <= midiMax) folded += 12
    while (folded > midiMax && folded - 12 >= midiMin) folded -= 12

    // Prefer the octave nearest where the line already is, so a voice sitting
    // on the edge of the lane's range doesn't flip up and down between frames.
    if (previous !== null) {
      for (const candidate of [ folded - 12, folded + 12 ]) {
        if (candidate < midiMin || candidate > midiMax) continue
        if (Math.abs(candidate - previous) < Math.abs(folded - previous)) folded = candidate
      }
    }
    return folded
  }

  roundedRect(x, y, width, height, radius) {
    const context = this.context
    const r = Math.min(radius, height / 2, width / 2)
    context.beginPath()
    context.moveTo(x + r, y)
    context.arcTo(x + width, y, x + width, y + height, r)
    context.arcTo(x + width, y + height, x, y + height, r)
    context.arcTo(x, y + height, x, y, r)
    context.arcTo(x, y, x + width, y, r)
    context.closePath()
  }

  dispose() {
    this.observer.disconnect()
  }
}
