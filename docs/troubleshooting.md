# Troubleshooting

When "the site is down", trace the request from the outside in. Stop at the
first layer that fails.

| Layer | Check | Typical cause |
|---|---|---|
| DNS | `dig +short example.com` | Wrong record, stale TTL after a move |
| CDN | `curl -I https://example.com` and look at the `server` / `via` headers | Cache serving an old error, wrong origin |
| TLS | `curl -vI https://example.com 2>&1 \| grep -i expire` | Expired or mismatched certificate |
| Web server | `sudo nginx -t` and `sudo tail -f /var/log/nginx/error.log` | Config typo, wrong `root` or socket path |
| PHP-FPM | `systemctl status php8.3-fpm` and `ls /run/php/` | Service down, socket name changed after a PHP upgrade |
| Application | `tail -f /var/www/app/shared/storage/logs/laravel.log` | Missing `.env` value, exception after deploy |
| Permissions | `ls -ld /var/www/app/shared/storage` | `storage` not writable by `www-data` |
| Database | `php artisan tinker` then `DB::select('select 1')` | Wrong host, RDS security group, credentials |

## Deploy-specific problems

**Site shows old code after a deploy.** Check that `fastcgi_param
SCRIPT_FILENAME $realpath_root$fastcgi_script_name;` is in the Nginx config,
then `sudo systemctl reload php8.3-fpm`.

**`Permission denied` writing logs or cache.** Re-apply the layout from the
bootstrap script: group `www-data`, mode `2775` on `shared/storage`.

**Deploy fails on SSH.** Confirm `DEPLOY_KNOWN_HOSTS` holds fresh output of
`ssh-keyscan <host>`, and that the key is in the deploy user's
`authorized_keys`.

**Deploy rolled itself back.** Read the CI log: either `migrate` failed or the
health check URL did not return a 2xx. The previous release stays live.

**Need to roll back by hand.** `APP_DIR=/var/www/app ./scripts/rollback.sh`.
This does not reverse migrations.
