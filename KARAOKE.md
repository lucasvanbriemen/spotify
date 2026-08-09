# Karaoke mode — improvement plan

Current state: `app/views/karaoke/index.html.erb`, `app/javascript/controllers/karaoke_controller.js`,
`app/assets/stylesheets/karaoke.scss`, `app/services/vocal_separation.rb`, `script/karaoke_separate.py`.

What exists works end to end — synced-lyrics search, vocal-free playback, a word sweep, and live pitch
scoring. What it *reads* as is a lyrics player with a meter attached, not a karaoke machine. This plan
closes that gap.

---

## 1. What the established apps actually do

Researched: SingStar / UltraStar Deluxe (the genre-defining scoring UI), Smule, Apple Music Sing,
Singa/KaraFun (streaming karaoke), and the CDG/hardware karaoke-machine conventions.

| Convention | Who does it | We have |
|---|---|---|
| **Pitch lane** — target notes as horizontal bars on a scrolling piano roll, singer's pitch drawn live on top, bars light up when hit | SingStar, UltraStar, Smule, StarMaker | ✗ (we have the data, show none of it) |
| **Per-line verdict popups** — "Perfect / Great / Good / Bad" after each phrase | UltraStar, SingStar | ✗ |
| **Points + combo/streak**, not a raw running average | every karaoke game | ✗ (live % only) |
| **Golden/bonus notes** | SingStar, UltraStar | ✗ |
| **Two-line lyric block, anchored** — current line + next line, big, bottom of screen, wipe-highlight left→right | CDG standard, every machine, Smule | ✗ (centred smooth-scrolling list — that's the *Apple Music lyrics* pattern, not karaoke) |
| **Count-in** — 3·2·1 at song start, and pulsing dots before each line after a gap | universal | ✗ |
| **Vocal guide / vocal fader** — blend the original vocal back in at any level | Apple Music Sing's headline feature; "guide melody" on every hardware machine | ✗ (stem is deleted) |
| **Key change (transpose) ± semitones**, tempo | every karaoke machine | ✗ |
| **Mic monitoring + reverb/echo** | every karaoke machine | ✗ |
| **Results screen** — grade, breakdown, best line, sing again | SingStar, Smule, UltraStar | ✗ (one line of text) |
| **Lean-back full-screen** — blurred art backdrop, no chrome, screen stays awake | Singa/KaraFun TV apps | partial |
| **Queue / party mode** — line up songs, prepare next while current plays | KaraFun, Singa, every KJ setup | ✗ |
| **Word-level timing** from Enhanced LRC (`<mm:ss.xx>` per word) | the actual karaoke lyric standard | ✗ (estimated from character count) |

Sources: [Apple Music Sing](https://www.apple.com/newsroom/2022/12/apple-introduces-apple-music-sing/) ·
[UltraStar](https://en.wikipedia.org/wiki/UltraStar) ·
[Enhanced LRC / A2 spec](https://www.quicklrc.com/subtitle-formats/enhanced-lrc) ·
[Singa](https://singa.com/blog/best-karaoke-apps/) ·
[karaoke machine feature baseline](https://www.sweetwater.com/insync/karaoke-buying-guide/)

---

## 2. Foundation problems to fix first

These are correctness issues underneath the UI. Any visual work built on top of them will look broken.

**a. Everything renders at ~4 Hz.** `updateActiveLine` / `updateScoring` hang off `audio.ontimeupdate`,
which browsers fire roughly 4×/second (`karaoke_controller.js:239`). The word sweep therefore jumps in
250 ms steps, and scoring samples the mic at 4 Hz while the worklet produces ~20 Hz — most of the
singer's pitch data is thrown away. Move lyric sweep, pitch lane and scoring onto a
`requestAnimationFrame` loop reading `audio.currentTime`; keep `ontimeupdate` only for the seek bar.

**b. Scoring is systematically offset by unmeasured latency.** Mic capture latency plus
`AudioContext.outputLatency` is typically 20–150 ms; over a fast melody that is most of a note. Compare
the live pitch against `currentTime - (outputLatency + inputLatency)`, and add a one-time **mic check**
screen (sing a note, confirm the meter moves) that can also cross-correlate to calibrate the offset.

**c. Word timings are guessed from word length.** `prepareLines` weights each word by
`word.length + 1` (`karaoke_controller.js:335`) — visibly wrong on held notes and short filler words.
Two fixes, in order of payoff: prefer word-level lyrics when the source has them, and otherwise derive
timings from the isolated vocal stem, which we already analyse (see 3a).

**d. The average is diluted.** `scoreSamples` averages every scored frame across the whole song, so a
great chorus is dragged down by an awkward verse and the number stops moving after 90 seconds. Score
per note, then per line (see 5).

**e. State leaks on exit.** `back()` (`karaoke_controller.js:157`) leaves the mic open and doesn't reset
scoring; `showScoreSummary` silently does nothing without a mic.

---

## 3. Backend: produce the data the UI needs

### a. `notes.json` — quantised melody (unlocks the pitch lane)

`script/karaoke_separate.py` already runs `librosa.pyin` on the isolated vocal stem and writes a raw
25 ms `hz[]` curve. Add a second artifact next to it: median-filter the curve, convert to MIDI, split on
voiced gaps and on jumps over ~0.6 semitones, drop segments under ~80 ms, and emit

```json
{ "notes": [{ "start": 12.35, "end": 12.80, "midi": 67 }, …], "midi_min": 55, "midi_max": 76 }
```

That is the whole input to a SingStar-style pitch lane, per-note scoring, and difficulty rating — from
data we already compute. `midi_min/max` set the lane's vertical range so the notes fill the screen.

### b. `words.json` — real word timings

Within each LRC line, distribute words across the vocal stem's **voiced segments** in that time window
instead of by character count. A line's words map onto actual sung syllable onsets, which is far closer
than length-weighting and needs no new dependency. Where LRCLIB returns Enhanced-LRC word timestamps,
use those verbatim and skip the estimate.

### c. Keep the vocal stem (a deliberate reversal)

`script/karaoke_separate.py`'s docstring and `vocal_separation.rb:12` state that the vocal stem never
leaves the temp directory. A vocal-guide fader requires keeping it as `#{isrc}.vocals.mp3`. This is your
call — it is the single feature Apple leads Music Sing with, and it's what makes an unfamiliar song
singable, but it does mean caching an isolated vocal track on disk. Both comments must be updated if we
do it, since they currently document the opposite guarantee.

### d. Cache versioning

`VocalSeparation.ready?` is "whatever's on disk" (`vocal_separation.rb:40`). Adding artifacts means
existing caches are half-ready. Add `KARAOKE_ARTIFACT_VERSION` and a `#{isrc}.v2.json` manifest listing
what was produced; `ready?` requires the current version, and the UI degrades gracefully (no notes
file → no pitch lane, everything else still works) rather than blocking on a re-separation.

### e. Prepare-ahead

`prepare` already enqueues a job. Let the search screen kick off preparation on hover/selection and keep
browsing, so the several-minute Demucs wait overlaps with picking the next song — this is what makes a
queue (see 7) worth having.

---

## 4. The stage redesign

Replace the current centred column with the standard karaoke stage layout, full-bleed:

```
┌────────────────────────────────────────────────────────┐
│  ← 3:14 ─────────●──────  ♪ Song — Artist    124,500 ×8│  HUD: thin, top
├────────────────────────────────────────────────────────┤
│                                                        │
│      ▁▁▁▁      ▃▃▃▃▃▃                                  │  PITCH LANE
│  ▃▃▃▃    ▅▅▅▅▅▅      ▂▂▂▂▂▂▂▂   ← target notes         │  (scrolling
│  ～～～～～～～～～～  ← your pitch, drawn live         │   piano roll)
│                          │ now                         │
├────────────────────────────────────────────────────────┤
│                                                        │
│      I've paid my dues, time after time                │  ACTIVE LINE
│      ▔▔▔▔▔▔▔▔▔▔▔▔                                      │  (wipe fill)
│      I've done my sentence                             │  NEXT LINE (dim)
│                                                        │
└────────────────────────────────────────────────────────┘
     blurred album art, desaturated, behind everything
```

Concretely:

- **Anchored two-line lyric block** at the bottom third. The active line never moves; when it ends, the
  next line swaps up into place. Delete the `scrollIntoView` behaviour (`karaoke_controller.js:365`) —
  smooth-scrolling a centred list is a lyrics-reading pattern and it makes the eye chase the text.
- **Wipe highlight, not per-word colour swaps.** Render each line twice, stacked: a dim base layer and a
  bright layer clipped by `clip-path: inset(0 calc(100% - var(--sweep)) 0 0)`, driven per-frame. That is
  the CDG "colour wipe" look, and it's one CSS variable per frame instead of N class toggles.
- **Count-in.** A 3-2-1 ring at song start, and three pulsing dots above the next line when there's a gap
  over ~2 s before it starts. Singers need to know *when*, not just *what*.
- **Held notes undulate.** When a note in `notes.json` runs longer than ~700 ms, let its lyric text
  breathe/glow for the duration — Apple Music Sing's trick, and it reads as "hold this".
- **Backdrop.** Album art, heavily blurred and darkened, with a slow drift; it makes the screen feel like
  a venue rather than a form. Consider a subtle beat-reactive pulse from the instrumental's RMS.
- **Type scale up.** `1.6rem` (`karaoke.scss:274`) is a phone-reading size. Karaoke text is read from
  across a room: clamp roughly `2.4rem`–`5rem`, weight 700+, and make the whole stage a real full-screen
  view (Fullscreen API + `navigator.wakeLock`) with a hidden-until-hover control bar.

## 5. Scoring that feels like a game

Move from "average of every frame" to the note-based model the genre uses:

- **Per note**: from `notes.json`, compare the singer's pitch across the note's span; award
  `hit_ratio × note_duration` points. Keep the existing octave folding — it's correct and generous in the
  right way.
- **Per line**: pop a verdict at the end of each line — Perfect / Great / Good / Miss — near the lyric,
  the way UltraStar does. This is the single biggest "feels like karaoke" change and it costs almost
  nothing.
- **Combo**: consecutive lines at Good or better multiply the score; a miss resets it. The multiplier is
  visible in the HUD.
- **Golden notes**: mark the top ~10% longest/highest notes as bonus, double points, distinct gold styling
  in the lane. Pure flavour, hugely recognisable.
- **Live meter → pitch lane.** The current bar (`karaoke.scss:229`) becomes redundant once the lane shows
  the same information more richly; keep a slim "sharp/flat" indicator instead, since knowing the
  *direction* of the error is what actually helps a singer correct.
- **Results screen**: grade (S/A/B/C/D) over a big number, breakdown by pitch accuracy / timing / notes hit,
  the best-performing line quoted back, a sparkline of accuracy over the song, and *Sing again* /
  *Next in queue*. Persist scores per ISRC so there's a personal best to beat.

## 6. Karaoke controls

A control bar (hidden until hover/tap) with the things every karaoke machine has:

- **Vocal guide fader** — 0–100% of the original vocal, blended over the instrumental (needs 3c). Default
  ~20% for an unfamiliar song, 0% once confident.
- **Key change** — ±6 semitones. `preservesPitch = false` on the audio element only shifts by changing
  rate; doing it properly means a Web Audio phase vocoder, or pre-rendering shifted variants server-side
  with ffmpeg `rubberband`. Reference pitch shifts by the same amount so scoring stays honest.
- **Mic level + monitoring + reverb** — a `ConvolverNode` or `DelayNode` on the mic path. Only safe on
  headphones; gate it behind a warning about feedback through speakers.
- **Guide melody toggle** — a synthesised sine following `notes.json`, the classic hardware "melody guide".
- Note: `getUserMedia` currently requests `echoCancellation` and `noiseSuppression`
  (`karaoke_controller.js:409`). Both are tuned for speech and will fight a singing voice and mangle pitch
  detection — turn them off, and `autoGainControl` too.

## 7. Session flow

- **Queue / party mode**: add songs to a list, prepare the next while the current one plays, auto-advance,
  optional singer names per entry. This is what turns it from a single-song toy into something you'd
  actually run at a party.
- **Search screen**: show which songs are already prepared (instant start) vs cold; surface recent and
  most-sung; show difficulty derived from `notes.json` (range + average note length) and the song's key.
- **Preparation**: replace the text status (`karaoke_controller.js:207`) with a real staged progress UI —
  download → separate → analyse — with an honest estimate, and let the user keep browsing while it runs.
- **Duets**: LRC line prefixes (`M:`/`F:`/`v1:`/`v2:`) exist in some sources; when present, split lines
  left/right like Apple Music Sing's duet view.

---

## 8. Suggested order

| Phase | Work | Why here |
|---|---|---|
| **1. Foundation** | rAF render loop, latency calibration + mic check, fix `back()` leaks, drop `echoCancellation`/`noiseSuppression` | everything else sits on top of this; also makes the *existing* feature visibly better |
| **2. Stage redesign** | anchored two-line block, wipe highlight, count-in, backdrop, full-screen + wake lock, type scale | biggest perceived change per unit of work; no backend needed |
| **3. Pitch lane** | `notes.json` in the separation script + cache versioning, scrolling piano-roll canvas | the defining karaoke-game visual, from data we already have |
| **4. Game scoring** | per-note points, line verdicts, combo, golden notes, results screen, personal bests | turns the meter into a game |
| **5. Controls** | vocal fader (needs the stem decision), key change, mic FX, guide melody | the hardware-parity features |
| **6. Session** | queue, prepare-ahead, richer search, duets | party-ready |

Phases 1 and 2 are independent of the backend and deliver most of the "feels like a karaoke app"
difference on their own. Phase 3 is where it stops looking like a lyrics player entirely.

## 9. Open questions

1. **Vocal stem on disk** (3c) — the code currently promises the opposite. Yes or no?
2. **Primary target** — phone in hand, laptop, or a TV across the room? It changes type scale, control
   sizing, and whether the pitch lane or the lyrics get the vertical space.
3. **Key change** — worth a server-side pre-render with ffmpeg, or skip it for now?
4. **Multiplayer** — is one mic / one singer the scope, or should scoring eventually handle two?
