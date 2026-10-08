#!/usr/bin/env bash
# Manually roll back to the previous release.
# Usage: rollback.sh            (switches to the release before the current one)
#
# Note: this does NOT undo database migrations. Write migrations to be
# backward-compatible so the previous release keeps working after a rollback.
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/var/www/app}"
PHP_FPM_SERVICE="${PHP_FPM_SERVICE:-php8.3-fpm}"
RELEASES_DIR="$APP_DIR/releases"
CURRENT_LINK="$APP_DIR/current"

current="$(readlink -f "$CURRENT_LINK")"

# Newest first; pick the first release that is not the current one.
previous=""
while IFS= read -r dir; do
  dir="${dir%/}"
  if [[ "$(readlink -f "$dir")" != "$current" ]]; then
    previous="$dir"
    break
  fi
done < <(ls -1dt "$RELEASES_DIR"/*/)

if [[ -z "$previous" ]]; then
  echo "No previous release found" >&2
  exit 1
fi

echo "Rolling back: $current -> $previous"
ln -sfn "$previous" "$CURRENT_LINK.tmp"
mv -Tf "$CURRENT_LINK.tmp" "$CURRENT_LINK"
sudo systemctl reload "$PHP_FPM_SERVICE"
echo "Done"
