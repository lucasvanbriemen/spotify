# LTVB Radio

Radio-style listening for the music app: tap a station in the new **Radio**
tab and music plays continuously, interrupted now and then by a spoken news
bulletin, a DJ intro or a weather/time check — generated on the server from
real headlines (NOS/BBC) with OpenAI (scripts + text-to-speech).

## To do before it works

1. **Server `.env`** (`/var/www/vhosts/ltvb.nl/music.ltvb.nl/.env`) — add the
   new keys from `.env.example`. Only one is required:
   * `OPENAI_API_KEY` — **required**; without it, stations still play music
     but no news/intros/weather are generated.
   * `OPENAI_TEXT_MODEL` (default `gpt-4o-mini`), `TTS_VOICE_NL` /
     `TTS_VOICE_EN` (default `cedar`; `marin` is a brighter alternative),
     `STATION_LAT`/`STATION_LON` (default Amsterdam), `RADIO_LOCALE` (default
     `nl`) — all optional. The OpenAI speech request also receives
     language- and segment-specific performance direction for DJ links,
     bulletins, and weather checks.
2. **Plesk Scheduled Task** (one-time, manual — this is the big one). Nothing
   starts the Solid Queue worker under Passenger, so recurring jobs (news
   bulletins, enrichment, cleanup) and async cache warmups never run without
   it. In Plesk, add a task for the subscription user, **every minute**:
   ```
   /var/www/vhosts/ltvb.nl/music.ltvb.nl/script/solid_queue_runner.sh >> /var/www/vhosts/ltvb.nl/music.ltvb.nl/log/solid_queue.log 2>&1
   ```
   (`flock` inside the script makes it a no-op while a worker is already
   running, and an auto-restart after crashes/deploys.) This also fixes the
   pre-existing bug that `prepare` warmups silently never ran in production.
3. **Deploy** — push as usual; `plesk_deploy.sh` runs `bundle install` (new
   gems: `rss`, a `minitest` pin), `db:prepare` (3 new migrations) and now
   kills the old worker so cron relaunches it on the new code.
4. **Verify, in order:**
   * `GET /api/stats` → `"queue_healthy": true` (within a minute of the task
     existing).
   * After the next top of the hour: `storage/audio/talk-news-nl-*.mp3`
     appears (news job runs at :01 NL, :03 EN).
   * `GET /api/stations` → smart stations (Morning/Discovery) immediately;
     genre/decade stations appear as enrichment fills in metadata — the
     backfill does ~240 songs/hour, so the full library takes a few hours.
5. **iOS app** — just build & run (all three targets already build). The
   Radio tab is second; nothing to configure.
6. **Before committing:** two files carry your local dev-tunnel edits that
   shouldn't ship — `ios/music/shared/ServerApi.swift` (hardcoded
   devtunnels URL + a `print`) and `config/environments/development.rb`
   (devtunnels host entry).

Later / optional: if OpenAI's Dutch accent annoys you, the TTS call sits
behind `TTS_PROVIDER` (`app/services/tts/client.rb`) — an ElevenLabs or
Google provider is a ~30-line class, no pipeline changes.

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
existing library is backfilled by `EnrichSongsJob` (every 10 min, rate-limit
friendly). Spoken language is `RADIO_LOCALE` with per-station overrides in
`Station::LANGUAGE_OVERRIDES` (e.g. `"genre-rock" => "en"`).

### The queue loop

The app fetches `GET /api/station/{id}/queue?count=10`;
`StationQueueBuilder` samples songs (never twice in a chunk, nothing you
played in the last 6 hours, weighted for smart stations), interleaves talk
items, and returns everything in the same JSON shape as songs plus
`kind: "song" | "talk"`. The app plays items through the normal
`get-mp3/{id}` path (talk files live in `storage/audio/` too, so Apache
X-Sendfile serving is unchanged) and silently refills when ≤ 2 items remain —
the radio never ends. Play reporting now carries `station_id`; talk items are
never counted in stats.

### Talk segments

`TalkSegment` rows + MP3s under `storage/audio/talk-*.mp3`:

* **News** — hourly per language: RSS headlines → OpenAI writes a 120–200
  word bulletin (NOS-journaal style) → OpenAI TTS → `bin/ffmpeg` loudness
  normalization (TTS is quieter than mastered music). A station airs the
  current hour's bulletin at most once per ~18 minutes of listening.
* **DJ intros** — "Dat was X… hierna Y" every ~3rd transition, generated in
  the background per transition (deterministic id, so chunks reuse them). If
  the LLM is down, a static template fills in.
* **Weather/time** — every ~45 min, pure template (no LLM): open-meteo
  conditions + colloquial Dutch clock ("Het is ongeveer kwart over negen").
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

Hourly bulletins in two languages plus intros ≈ **€1–2/month** on OpenAI
(the TTS is the main cost; scripts are pennies).
