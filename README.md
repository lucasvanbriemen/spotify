# Music

Rails 8 backend for the music app (Deezer-powered search, playlists, MP3
fetching via yt-dlp, play tracking). Serves the JSON API used by the iOS app
in `ios/`.

## Setup

* Ruby 3.3.8 (see `.ruby-version`)
* `bundle install`
* Clone [`ui-components`](https://github.com/lucasvanbriemen/ui-components)
  next to this checkout (or point `SHARED_UI_PATH` at it). It provides the
  shared view helpers — `button`, `CustomFormBuilder` — and stylesheets that
  `config/application.rb` adds to the view/helper/asset paths. **Without it
  every page raises `uninitialized constant CustomFormBuilder`.**
* Copy `.env.example` to `.env` and fill in the MySQL/MariaDB credentials
  (database `music`). Set `LOCAL_DEV_ACCOUNT` too, or every request redirects
  to login.ltvb.nl.
* `bin/rails db:prepare`
* `bin/dev` to run the server (port 3000)

## Tests

* `bin/rails test`
* `bin/test-js` for the karaoke engine's JavaScript unit tests

## Notes

* `bin/yt-dlp`, `bin/ffmpeg` and `bin/ffprobe` must be present for MP3
  downloads; they are gitignored (symlinks into a package manager's bin are
  fine). Downloaded audio is cached under `storage/audio/`.
* Karaoke separation needs the Python venv at `vendor/karaoke/` (also
  gitignored). Create it with a Python 3.12+ interpreter and
  `pip install demucs librosa soundfile numpy`; `script/karaoke_separate.py`
  and `script/check_audio_alignment.py` run out of it. The first Demucs run
  downloads ~80MB of model weights.
* If YouTube starts answering downloads with `HTTP Error 403`, the player
  client yt-dlp picks is the usual cause. `YTDLP_PLAYER_CLIENTS` overrides the
  list that `app/services/yt_dlp.rb` walks, without a deploy.

## Offloading karaoke work to a GPU box

Preparing a song is dominated by htdemucs: ~205s of a ~250s prepare on the
production box, which has six vCPU and no graphics card. That is only just
faster than a song is long, so a queue of singers waits on each other. The same
separation takes ~38s on a consumer GPU.

So every expensive command runs through a `ComputeSession` (`app/services/`),
which is a scratch directory either on this host or on another machine reached
over SSH. `script/gpu_agent.py` is the far end: prod stages inputs into a work
directory there, runs the same argv it would have run locally, and fetches the
finished artifacts back. The downloads go across too — not for the GPU, but for
the address: the whole `YtDlp` player-client walk exists because YouTube serves
the datacenter IP a blanket 403, and a home connection is not treated that way.

**With none of this configured, nothing changes** — every prepare runs locally
exactly as before. Set `KARAOKE_GPU_SSH` to turn it on:

| variable | |
|---|---|
| `KARAOKE_GPU_SSH` | `user@host`. Unset means "no offload". |
| `KARAOKE_GPU_ROOT` | the checkout on that box, e.g. `C:/Users/karaoke/music`. Every other path is derived from it. |
| `KARAOKE_GPU_EXE_SUFFIX` | `.exe` by default (the box is Windows); set it empty for a Linux GPU host. |
| `KARAOKE_GPU_DEVICE` | torch device for demucs, `cuda` by default. |
| `KARAOKE_GPU_PYTHON`, `KARAOKE_GPU_AGENT` | override the derived paths individually. |
| `KARAOKE_GPU_SSH_KEY` | an identity file, when the default keys are not the right ones. |
| `KARAOKE_LOCAL_DEVICE` | torch device for a *local* run — `mps` on an Apple laptop is ~8x its CPU. |

The box needs the same things this host does: a checkout, the `vendor/karaoke/`
venv, and `bin/yt-dlp` + `bin/ffmpeg`. Verify all of it with:

```sh
bin/rails karaoke:gpu:probe   # what the box says about itself: torch, CUDA, tools
bin/rails karaoke:gpu:check   # round-trips a real file through exec/put/fetch/release
```

Two properties worth keeping if you touch this:

* **No variable data ever reaches a remote shell.** The SSH command is fixed
  (`ssh <target> <python> <agent.py>`); argv, filenames and sizes travel as JSON
  on stdin. The box runs Win32-OpenSSH, so a remote command string is parsed by
  `cmd.exe`, and a song title is quite enough to break that.
* **The local path is not a separate implementation.** It is the same
  orchestration with a different back end, so it is exercised by the same tests
  and cannot quietly rot while the GPU box is doing all the work.

If the box is asleep or unreachable, `GpuHost` retries it a few times and then
falls back to running locally — slow, but a party should not stop because a
desktop went to sleep. Which host ran a given song is in the log, tagged
`[compute]`.
