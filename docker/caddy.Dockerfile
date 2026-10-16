FROM caddy:2.10-alpine

WORKDIR /srv
RUN mkdir -p /srv/public

# Caddy only needs the public entrypoint and static assets. PHP application
# code remains exclusively in the PHP-FPM image.
COPY public/index.php /srv/public/index.php
COPY assets /srv/assets
COPY docker/Caddyfile /etc/caddy/Caddyfile
RUN ln -s ../assets /srv/public/assets
