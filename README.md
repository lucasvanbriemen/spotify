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
