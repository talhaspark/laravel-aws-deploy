#!/usr/bin/env bash
# One-time server preparation for Ubuntu 24.04 (EC2 or Lightsail). Run as root.
#
# Usage: sudo ./bootstrap-ubuntu.sh [deploy-user] [app-dir]
#
# It installs Nginx and PHP-FPM, creates a non-root deploy user, builds the
# release directory layout and allows that user to reload PHP-FPM without a
# password. It does not touch your database, DNS or TLS certificates.
set -Eeuo pipefail

DEPLOY_USER="${1:-deploy}"
APP_DIR="${2:-/var/www/app}"
PHP_VERSION="${PHP_VERSION:-8.3}"

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx unzip curl git \
  "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-cli" "php${PHP_VERSION}-mysql" \
  "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml" "php${PHP_VERSION}-curl" \
  "php${PHP_VERSION}-bcmath" "php${PHP_VERSION}-zip"

# Deploy user (key-only login; add the CI public key to its authorized_keys).
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi
usermod -aG www-data "$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
touch "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"

# Release layout. Group-writable + setgid so PHP-FPM (www-data) and the deploy
# user can both write Laravel's storage directory.
install -d -o "$DEPLOY_USER" -g www-data -m 2775 "$APP_DIR" "$APP_DIR/releases" "$APP_DIR/shared"
install -d -o "$DEPLOY_USER" -g www-data -m 2775 \
  "$APP_DIR/shared/storage" \
  "$APP_DIR/shared/storage/app" \
  "$APP_DIR/shared/storage/framework" \
  "$APP_DIR/shared/storage/framework/cache" \
  "$APP_DIR/shared/storage/framework/sessions" \
  "$APP_DIR/shared/storage/framework/views" \
  "$APP_DIR/shared/storage/logs"

# Let the deploy user reload PHP-FPM, and nothing else, without a password.
SUDOERS_FILE="/etc/sudoers.d/${DEPLOY_USER}-php-fpm"
echo "$DEPLOY_USER ALL=(root) NOPASSWD: /usr/bin/systemctl reload php${PHP_VERSION}-fpm" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE"

systemctl enable --now nginx "php${PHP_VERSION}-fpm"

cat <<EOF

Bootstrap complete. Remaining manual steps:
  1. Add the CI public key to /home/$DEPLOY_USER/.ssh/authorized_keys
  2. Create $APP_DIR/shared/.env (chmod 640, owner $DEPLOY_USER:www-data)
  3. Copy server/nginx.conf.example to /etc/nginx/sites-available/app and enable it
  4. Point DNS at this server, then run certbot for HTTPS
EOF
