#!/usr/bin/env bash
# Server-side release script. Runs on the EC2/Lightsail host (invoked over SSH by CI).
#
# Usage: deploy.sh <release-id> <path-to-release.tar.gz>
#
# Layout it manages:
#   $APP_DIR/releases/<release-id>/   one directory per release
#   $APP_DIR/shared/.env              persistent environment file
#   $APP_DIR/shared/storage/          persistent Laravel storage
#   $APP_DIR/current -> releases/...  symlink Nginx serves from
set -Eeuo pipefail

RELEASE_ID="${1:?release id required}"
ARCHIVE="${2:?archive path required}"

APP_DIR="${APP_DIR:-/var/www/app}"
KEEP="${KEEP:-5}"
PHP_FPM_SERVICE="${PHP_FPM_SERVICE:-php8.3-fpm}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"
HEALTHCHECK_RETRIES="${HEALTHCHECK_RETRIES:-10}"

RELEASES_DIR="$APP_DIR/releases"
SHARED_DIR="$APP_DIR/shared"
NEW_RELEASE="$RELEASES_DIR/$RELEASE_ID"
CURRENT_LINK="$APP_DIR/current"
PREVIOUS_RELEASE="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"

log() { printf '[deploy] %s\n' "$*"; }

switch_to() {
  # Atomic symlink swap: create a temp link, then rename over the old one.
  ln -sfn "$1" "$CURRENT_LINK.tmp"
  mv -Tf "$CURRENT_LINK.tmp" "$CURRENT_LINK"
}

reload_php() {
  sudo systemctl reload "$PHP_FPM_SERVICE"
}

rollback() {
  if [[ -n "$PREVIOUS_RELEASE" && -d "$PREVIOUS_RELEASE" ]]; then
    log "Rolling back to $PREVIOUS_RELEASE"
    switch_to "$PREVIOUS_RELEASE"
    reload_php
  else
    log "No previous release to roll back to"
  fi
}

on_error() {
  log "Deploy failed; cleaning up $NEW_RELEASE"
  # If the new release was already live, put the old one back first.
  if [[ "$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)" == "$NEW_RELEASE" ]]; then
    rollback
  fi
  rm -rf "$NEW_RELEASE"
}
trap on_error ERR

mkdir -p "$RELEASES_DIR" "$SHARED_DIR/storage"

log "Unpacking $RELEASE_ID"
mkdir -p "$NEW_RELEASE"
tar -xzf "$ARCHIVE" -C "$NEW_RELEASE"

log "Linking shared files"
[[ -f "$SHARED_DIR/.env" ]] || { echo "Missing $SHARED_DIR/.env" >&2; exit 1; }
ln -sfn "$SHARED_DIR/.env" "$NEW_RELEASE/.env"
rm -rf "$NEW_RELEASE/storage"
ln -sfn "$SHARED_DIR/storage" "$NEW_RELEASE/storage"

cd "$NEW_RELEASE"

log "Running migrations"
php artisan migrate --force

log "Rebuilding caches"
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache

log "Switching to new release"
switch_to "$NEW_RELEASE"
reload_php
php artisan queue:restart || true

if [[ -n "$HEALTHCHECK_URL" ]]; then
  log "Health check: $HEALTHCHECK_URL"
  ok=0
  for ((i = 1; i <= HEALTHCHECK_RETRIES; i++)); do
    if curl -fsS --max-time 5 -o /dev/null "$HEALTHCHECK_URL"; then
      ok=1
      break
    fi
    sleep 2
  done
  if [[ "$ok" -ne 1 ]]; then
    log "Health check failed after $HEALTHCHECK_RETRIES attempts"
    false # triggers the ERR trap, which rolls back
  fi
fi

log "Pruning old releases (keeping $KEEP)"
# shellcheck disable=SC2012
ls -1dt "$RELEASES_DIR"/*/ | tail -n +$((KEEP + 1)) | xargs -r rm -rf

rm -f "$ARCHIVE"
log "Release $RELEASE_ID is live"
