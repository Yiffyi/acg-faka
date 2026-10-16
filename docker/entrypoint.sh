#!/bin/sh
set -eu

cd /var/www/html

DATA=/data
SKEL=/opt/acg-skel

# Runtime-writable directories live in the data volume so deployments and image
# upgrades do not replace configuration, uploads, plugins, themes or caches.
for name in config install assets_cache plugins pay themes runtime; do
    if [ ! -e "${DATA}/${name}" ]; then
        cp -a "${SKEL}/${name}" "${DATA}/${name}"
    fi
done

mkdir -p \
    "${DATA}/runtime/log" "${DATA}/runtime/plugin" "${DATA}/runtime/request" \
    "${DATA}/runtime/tmp" "${DATA}/runtime/view" "${DATA}/runtime/waf" \
    "${DATA}/runtime/session" "${DATA}/install/OS" "${DATA}/install/Update"

# Keep the public favicon in the persistent upload directory. The public tree
# exposes the repository-root favicon through a relative symlink.
if [ ! -f "${DATA}/assets_cache/favicon.ico" ] && [ -f /usr/local/share/acg-faka/favicon.ico ]; then
    cp /usr/local/share/acg-faka/favicon.ico "${DATA}/assets_cache/favicon.ico"
fi
if [ ! -L favicon.ico ]; then
    if [ -f favicon.ico ] && [ -s favicon.ico ]; then
        cp favicon.ico "${DATA}/assets_cache/favicon.ico"
    fi
    rm -f favicon.ico
    ln -s assets/cache/favicon.ico favicon.ico
fi

chown -R www-data:www-data \
    "${DATA}/config" "${DATA}/install" "${DATA}/assets_cache" \
    "${DATA}/plugins" "${DATA}/pay" "${DATA}/themes" "${DATA}/runtime"

# PHP-FPM clears its environment by default. Keep the database variables and
# generate the Redis-backed session configuration only when Redis is configured.
SESSION_INI=/usr/local/etc/php/conf.d/zz-acg-session.ini
if [ -n "${ACG_REDIS_HOST:-}" ]; then
    printf 'session.save_handler = redis\nsession.save_path = "tcp://%s:%s?database=%s&prefix=acg_sess:"\n' \
        "${ACG_REDIS_HOST}" "${ACG_REDIS_PORT:-6379}" "${ACG_REDIS_DB:-1}" > "${SESSION_INI}"
else
    printf 'session.save_handler = files\nsession.save_path = "/var/www/html/runtime/session"\n' > "${SESSION_INI}"
fi

if [ -n "${ACG_DB_PASSWORD_FILE:-}" ] && [ -r "${ACG_DB_PASSWORD_FILE}" ]; then
    ACG_DB_PASSWORD="$(cat "${ACG_DB_PASSWORD_FILE}")"
    export ACG_DB_PASSWORD
fi

exec "$@"
