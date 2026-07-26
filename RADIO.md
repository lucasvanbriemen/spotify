# LTVB Radio

Radio-style listening for the music app: tap a station in the new **Radio**
tab and music plays continuously, interrupted now and then by a spoken news
bulletin, a DJ intro or a weather/time check — generated on the server from
BBC headlines with OpenAI (scripts) and self-hosted Kokoro (speech).

## To do before it works

1. **Server `.env`** (`/var/www/vhosts/ltvb.nl/music.ltvb.nl/.env`):
   * `OPENAI_API_KEY` writes the English scripts.
   * `TTS_PROVIDER=kokoro` renders speech locally without an API subscription.
     `KOKORO_VOICE_HOST` and `KOKORO_VOICE_COHOST` select two English voices.
   * `STATION_LAT`/`STATION_LON` optionally move the weather away from the
     Amsterdam default.
2. **Supervisor** (one-time server setup). Passenger only manages web
   processes, so Solid Queue and the persistent Kokoro model run as dedicated
   Supervisor programs. Install the checked-in programs and narrowly scoped
   deployment sudo rule:
   ```
   install -o root -g root -m 0644 config/supervisor/music-solid-queue.conf /etc/supervisor/conf.d/music-solid-queue.conf
   install -o root -g root -m 0644 config/supervisor/music-kokoro.conf /etc/supervisor/conf.d/music-kokoro.conf
   install -o root -g root -m 0440 config/supervisor/ltvb-music-solid-queue.sudoers /etc/sudoers.d/ltvb-music-solid-queue
   visudo -cf /etc/sudoers.d/ltvb-music-solid-queue
   supervisorctl reread
   supervisorctl update
   ```
   Supervisor starts the worker at boot, restarts it after crashes, and writes
   output to `log/solid_queue.log`. This also fixes the pre-existing bug that
   `prepare` warmups silently never ran in production.
3. **Deploy** — push as usual; `plesk_deploy.sh` runs `bundle install` (new
   gems: `rss`, a `minitest` pin), `db:prepare` (3 new migrations), asset
   compilation, and then restarts `music-solid-queue`.
4. **Verify, in order:**
   * `GET /api/stats` → `"queue_healthy": true` (within a minute of the task
     existing).
   * After the next top of the hour: `storage/audio/talk-news-en-*.mp3`
     appears (the English news job runs at :01).
   * `GET /api/stations` → smart stations (Morning/Discovery) immediately;
     genre/decade stations appear as enrichment fills in metadata — the
     backfill does ~240 songs/hour, so the full library takes a few hours.
5. **iOS app** — just build & run (all three targets already build). The
   Radio tab is second; nothing to configure.
6. **Before committing:** two files carry your local dev-tunnel edits that
   shouldn't ship — `ios/music/shared/ServerApi.swift` (hardcoded
   devtunnels URL + a `print`) and `config/environments/development.rb`
   (devtunnels host entry).

OpenAI speech remains available as a fallback by setting
`TTS_PROVIDER=openai`; ElevenLabs support also remains available but is not
required.

## How it works

### Stations (computed, not stored)

`app/models/station.rb` derives the station list from the library — there is
no stations table:

| Station | Source |
|---|---|
| `genre-*` (Rock, Pop, …) | every Deezer album genre with ≥ 15 songs |
| `decade-*` (80s, 90s, …) | every decade (from release year) with ≥ 15 songs |
| `smart-morning` | whole library, weighted by what you historically play 06:00–10:00 |
| `smart-party` | BPM ≥ 115 or popular, weighted by BPM + your play counts |
| `smart-focus` | BPM ≤ 110; plays **no** talk at all |
| `smart-discovery` | songs you've played at most once; intros announce the tracks |

Genre/decade metadata comes from Deezer: new songs get it on creation, the
existing library is backfilled by `EnrichSongsJob` (every 10 min,
rate-limit-friendly). The station output is English-only.

### The queue loop

The app fetches
`GET /api/station/{id}/queue?count=10&starts_in={estimated-seconds}`;
`StationQueueBuilder` samples songs (never twice in a chunk, nothing you
played in the last 6 hours, weighted for smart stations), interleaves talk
items, and returns everything in the same JSON shape as songs plus
`kind: "song" | "talk"`. The app plays items through the normal
`get-mp3/{id}` path (talk files live in `storage/audio/` too, so Apache
X-Sendfile serving is unchanged) and silently refills when ≤ 2 items remain —
the radio never ends. `starts_in` lets the server schedule by the time a queued
chunk will actually air rather than the time it was requested. Play reporting
now carries `station_id`; talk items are never counted in stats.

### Format clock and talk segments

Talk is scheduled by a fixed hourly format clock rather than random
interruptions:

| Clock time | Element |
|---|---|
| `:02` | current English news bulletin |
| `:17` | solo presenter link |
| `:32` | time and weather |
| `:47` | two-host link |

Each element has a ten-minute grace window and airs at the first suitable song
transition. A per-station clock claim prevents refilled queue chunks from
scheduling the same element twice. Focus stations retain their no-talk policy.

`TalkSegment` rows + MP3s under `storage/audio/talk-*.mp3`:

* **News** — hourly: BBC RSS headlines → OpenAI writes a concise,
  speech-first English bulletin → Kokoro → `bin/ffmpeg` loudness
  normalization. News gets a clean ending rather than music underneath it.
* **DJ links** — short, speech-first scripts tied to the outgoing and incoming
  songs. The `:47` link is a three-turn exchange rendered with two distinct
  local voices. If the LLM is down, a static handoff fills in.
* **Weather/time** — a deterministic open-meteo template, delivered at `:32`.
* **Talk-up transition** — for presenter and weather links, the app starts the
  next song quietly beneath the final three seconds of speech, then raises it
  smoothly to full volume. The same preloaded player continues, so the record
  never restarts. News remains dry. This is deliberately conservative until
  the music library has cue metadata marking the end of each instrumental
  intro and the start of vocals.
* **Transcripts as lyrics** — `song/{talk-id}/lyrics` returns the transcript
  (with coarse timestamps), so the news text scrolls in the player and on the
  ambient/TV view.
* **Cleanup** — bulletins expire after 24h, intros/weather after 6h; a daily
  job deletes expired rows + files (the song cache is untouched).

**Everything degrades to music.** RSS down → no bulletin this hour. LLM down
→ template intros. TTS down → a 10-minute circuit breaker stops new talk.
A talk file that failed to render → the app skips it. Worker dead → chunks
still build (intros render just-in-time on first request); `queue_healthy`
in `/api/stats` tells you.

### In the app

Radio tab (iOS) / Radio sidebar section (macOS). Station mode lives in
`PlayerManager`: shuffle is disabled (the server orders the queue), previous
still works, starting a playlist leaves radio mode, and playing a single song
from search behaves like a song request — the station continues afterwards.
The lock screen shows "LTVB Radio — {station}".

### Costs

There are four spoken elements per talk-enabled station hour, but transition
scripts are cached by song pair and clock claims avoid duplicates. Kokoro runs
locally, so there is no per-character speech cost.

### Programming references

The clock and transition design follows broadcast practice:

* DINFOS/AFN: ride instrumental song ramps and fades, using intro/outro cue
  metadata to keep speech off vocals.
* PRX: use a repeatable hourly broadcast clock, with limited floating breaks
  when exact placement must follow the program flow.
* MusicMaster: schedule voice tracks, liners and jingles as clock elements,
  with rotation and separation rules.

Kokoro is an Apache-2.0 licensed, 82-million-parameter open-weight model with
American and British English voices.
