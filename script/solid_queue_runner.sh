#!/bin/bash
# Keeps the Solid Queue worker (bin/jobs) alive on the Plesk host. Passenger
# only manages web processes, so recurring jobs and async warmups need their
# own supervisor: a Plesk Scheduled Task runs this script every minute, and
# flock -n makes it a no-op while a worker is already running — which doubles
# as an automatic restart within a minute after a crash or a deploy.
#
# One-time manual setup in Plesk (Scheduled Tasks, run as the subscription
# user, every minute):
#   /var/www/vhosts/ltvb.nl/music.ltvb.nl/script/solid_queue_runner.sh >> /var/www/vhosts/ltvb.nl/music.ltvb.nl/log/solid_queue.log 2>&1
set -euo pipefail
APP=/var/www/vhosts/ltvb.nl/music.ltvb.nl
BIN=/var/www/vhosts/ltvb.nl/.rbenv/versions/3.3.8/bin
cd "$APP"
export RAILS_ENV=production
mkdir -p "$APP/tmp"
exec /usr/bin/flock -n "$APP/tmp/solid_queue.lock" "$BIN/bundle" exec bin/jobs
