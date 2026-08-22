#!/bin/bash
# Post-deploy script run by the Plesk Git extension after each pull.
# Plesk executes every *line* of its "deployment actions" field as a
# separate shell, so the action there is a single line invoking this
# script, which can then use variables/traps like a normal script.
set -euo pipefail
APP=/var/www/vhosts/ltvb.nl/music.ltvb.nl
# The canonical rbenv root, and the one the systemd units below run from.
# /var/www/vhosts/ltvb.nl/.rbenv/versions/3.3.8 is the same install by another
# path (identical inode, same Gem.dir), so gems installed here are the gems the
# worker loads — but this path is root-owned and can't be moved by a webspace
# operation, so prefer it.
BIN=/opt/rbenv/versions/3.3.8/bin
# This app's three long-running processes: Puma (the site), the Solid Queue
# worker, and the local Kokoro speech service. All three hold Ruby/Python code
# in memory and so must be restarted to pick up a deploy.
UNITS=(ltvb-app@music.ltvb.nl ltvb-jobs-music-ltvb-nl ltvb-kokoro-music-ltvb-nl)
cd "$APP"

# Always restart on exit, even if a step fails, so disk code is never left
# stale. --no-block because this script may itself be running under one of
# these units: a blocking restart would wait on the process waiting on it.
#
# This replaces two mechanisms that had both silently died when the box moved
# from Apache+Passenger+supervisor to nginx+Puma+systemd: `touch tmp/restart.txt`
# (Passenger's reload signal, now a file nothing reads) and
# `supervisorctl restart music-solid-queue` (no such program any more, so it
# exited 1 and `set -e` aborted every deploy right here — which is why neither
# the site nor the worker had picked up new code since the migration).
# The narrowly scoped sudo rule lives at config/systemd/ltvb-music-units.sudoers.
trap 'sudo /usr/bin/systemctl restart --no-block "${UNITS[@]}"' EXIT

export RAILS_ENV=production
export SECRET_KEY_BASE_DUMMY=1
"$BIN/bundle" config unset --local without >/dev/null 2>&1 || true
"$BIN/bundle" install
"$BIN/bundle" exec rails db:prepare
"$BIN/bundle" exec rails assets:precompile
echo "DEPLOY_OK ($("$BIN/ruby" -v))"
