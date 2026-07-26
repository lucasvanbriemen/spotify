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
