#!/bin/bash
# Post-deploy script run by the Plesk Git extension after each pull.
# Plesk executes every *line* of its "deployment actions" field as a
# separate shell, so the action there is a single line invoking this
# script, which can then use variables/traps like a normal script.
set -euo pipefail
APP=/var/www/vhosts/ltvb.nl/music.ltvb.nl
BIN=/var/www/vhosts/ltvb.nl/.rbenv/versions/3.3.8/bin
cd "$APP"
# Always restart Passenger on exit, even if a step fails, so disk code is never left stale
trap 'mkdir -p "$APP/tmp" && touch "$APP/tmp/restart.txt"' EXIT
export RAILS_ENV=production
export SECRET_KEY_BASE_DUMMY=1
"$BIN/bundle" config unset --local without >/dev/null 2>&1 || true
"$BIN/bundle" install
"$BIN/bundle" exec rails db:prepare
"$BIN/bundle" exec rails assets:precompile
echo "DEPLOY_OK ($("$BIN/ruby" -v))"
