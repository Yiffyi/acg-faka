# syntax=docker/dockerfile:1

# The application image only contains PHP-FPM and the PHP/runtime dependencies.
# HTTP termination, TLS, the database and Redis are separate Compose services.
ARG PHP_VERSION=8.2
FROM php:${PHP_VERSION}-fpm-bookworm

ENV ACG_HOME=/var/www/html \
    COMPOSER_ALLOW_SUPERUSER=1

# Install extensions without keeping compiler toolchains in the final image.
COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
RUN --mount=type=secret,id=proxy_ca,required=false \
    set -eux; \
    ca_bundle=/tmp/acg-ca-bundle.crt; \
    if [ -f /run/secrets/proxy_ca ]; then \
        cat /etc/ssl/certs/ca-certificates.crt /run/secrets/proxy_ca > "${ca_bundle}"; \
    else \
        cp /etc/ssl/certs/ca-certificates.crt "${ca_bundle}"; \
    fi; \
    mkdir -p /tmp/acg-php-conf; \
    printf '%s\n' \
        'openssl.cafile=/tmp/acg-ca-bundle.crt' \
        'curl.cainfo=/tmp/acg-ca-bundle.crt' \
        > /tmp/acg-php-conf/ca.ini; \
    mkdir -p /tmp/acg-pecl /tmp/acg-pecl-tmp; \
    curl --fail --location --cacert "${ca_bundle}" \
        https://pecl.php.net/get/redis-6.3.0.tgz \
        --output /tmp/acg-redis.tgz; \
    tar -xzf /tmp/acg-redis.tgz -C /tmp/acg-pecl-tmp; \
    cp /tmp/acg-pecl-tmp/package.xml /tmp/acg-pecl/package.xml; \
    cp -a /tmp/acg-pecl-tmp/redis-6.3.0/. /tmp/acg-pecl/; \
    PHP_INI_SCAN_DIR="/usr/local/etc/php/conf.d:/tmp/acg-php-conf" \
    SSL_CERT_FILE="${ca_bundle}" \
    CURL_CA_BUNDLE="${ca_bundle}" \
    install-php-extensions \
        bcmath \
        curl \
        gd \
        mbstring \
        opcache \
        pdo_mysql \
        /tmp/acg-pecl \
        zip; \
    rm -rf /tmp/acg-ca-bundle.crt /tmp/acg-php-conf /tmp/acg-pecl /tmp/acg-pecl-tmp /tmp/acg-redis.tgz; \
    rm -f /usr/local/bin/install-php-extensions

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR ${ACG_HOME}

COPY docker/php-fpm.conf /usr/local/etc/php-fpm.d/zz-acg-faka.conf
COPY docker/php.ini      /usr/local/etc/php/conf.d/acg-faka.ini
COPY docker/entrypoint.sh /usr/local/bin/acg-faka-entrypoint

# The repository tracks vendor, so autoload generation is deterministic and does
# not require Composer network access during every image build.
COPY . ${ACG_HOME}

RUN set -eux; \
    mkdir -p \
        /usr/local/share/acg-faka \
        ${ACG_HOME}/assets/cache \
        ${ACG_HOME}/app/Pay \
        ${ACG_HOME}/app/Plugin \
        ${ACG_HOME}/app/View/User/Theme \
        ${ACG_HOME}/config \
        ${ACG_HOME}/kernel/Install/OS \
        ${ACG_HOME}/kernel/Install/Update \
        ${ACG_HOME}/runtime/log \
        ${ACG_HOME}/runtime/plugin \
        ${ACG_HOME}/runtime/request \
        ${ACG_HOME}/runtime/tmp \
        ${ACG_HOME}/runtime/view \
        ${ACG_HOME}/runtime/waf; \
    printf '%s\n' \
        '<?php' \
        'declare(strict_types=1);' \
        '' \
        'return [' \
        "    'driver' => 'mysql'," \
        "    'host' => ''," \
        "    'port' => 3306," \
        "    'database' => ''," \
        "    'username' => ''," \
        "    'password' => ''," \
        "    'charset' => 'utf8mb4'," \
        "    'collation' => 'utf8mb4_unicode_ci'," \
        "    'prefix' => ''," \
        '];' \
        > ${ACG_HOME}/config/database.php; \
    if [ -f ${ACG_HOME}/favicon.ico ]; then \
        cp ${ACG_HOME}/favicon.ico /usr/local/share/acg-faka/favicon.ico; \
    fi; \
    composer dump-autoload --optimize --no-interaction; \
    chmod +x /usr/local/bin/acg-faka-entrypoint; \
    mkdir -p /opt/acg-skel; \
    for pair in \
        "config:config" \
        "kernel/Install:install" \
        "assets/cache:assets_cache" \
        "app/Plugin:plugins" \
        "app/Pay:pay" \
        "app/View/User/Theme:themes" \
        "runtime:runtime"; \
    do \
        src="${ACG_HOME}/${pair%%:*}"; \
        name="${pair##*:}"; \
        mkdir -p "$(dirname "/opt/acg-skel/${name}")"; \
        mv "${src}" "/opt/acg-skel/${name}"; \
        ln -s "/data/${name}" "${src}"; \
    done; \
    chown -R www-data:www-data ${ACG_HOME} /opt/acg-skel; \
    chown -h www-data:www-data \
        ${ACG_HOME}/config ${ACG_HOME}/kernel/Install ${ACG_HOME}/assets/cache \
        ${ACG_HOME}/app/Plugin ${ACG_HOME}/app/Pay ${ACG_HOME}/app/View/User/Theme \
        ${ACG_HOME}/runtime; \
    chown www-data:www-data ${ACG_HOME}; \
    chmod 755 ${ACG_HOME}; \
    test -L ${ACG_HOME}/runtime

VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD php-fpm -t

ENTRYPOINT ["acg-faka-entrypoint"]
CMD ["php-fpm", "--nodaemonize"]
