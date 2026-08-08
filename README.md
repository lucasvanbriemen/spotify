# Music

Rails 8 backend for the music app (Deezer-powered search, playlists, MP3
fetching via yt-dlp, play tracking). Serves the JSON API used by the iOS app
in `ios/`.

## Setup

* Ruby 3.3.8 (see `.ruby-version`)
* `bundle install`
* Copy `.env.example` to `.env` and fill in the MySQL/MariaDB credentials
  (database `music`).
* `bin/rails db:prepare`
* `bin/dev` to run the server (port 3000)

## Tests

* `bin/rails test`

## Notes

* `bin/yt-dlp` and `bin/ffmpeg` must be present on the server for MP3
  downloads; they are gitignored. Downloaded audio is cached under
  `storage/audio/`.
* Karaoke mode (vocal-free instrumentals + a sung-melody reference for
  scoring) needs a Python venv at `vendor/karaoke/` — gitignored, set up once:
  ```
  python -m venv vendor/karaoke
  vendor/karaoke/bin/pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
  vendor/karaoke/bin/pip install demucs librosa soundfile
  ```
  (Windows: `vendor\karaoke\Scripts\pip.exe` instead of `vendor/karaoke/bin/pip`.
  Drop the CPU-only `--index-url` if the machine has an NVIDIA GPU set up for
  CUDA — Demucs runs much faster on one.) Used by `script/karaoke_separate.py`.
