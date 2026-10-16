# Docker Compose 部署

本项目的应用镜像只运行 PHP-FPM。Caddy、MariaDB 和 Redis 由
`docker-compose.yml` 分别编排，避免把 Web 服务器、数据库和缓存服务塞进同一个容器。

```bash
docker compose up -d --build
```

默认访问地址是 <http://localhost:8080>。数据保存在 `acg_data`、`acg_mysql`、
`acg_redis` 和 Caddy 的数据卷中。首次启动时 `secrets-init` 生成数据库密码，应用安装向导会
自动读取数据库主机、库名和账号；密码不会渲染到页面中。

常用配置：

```bash
ACG_HTTP_PORT=80 ACG_HTTPS_PORT=443 docker compose up -d --build
ACG_IMAGE=ghcr.io/lizhipay/acg-faka:3.8.4 docker compose up -d
```

Caddy 配置位于 [`Caddyfile`](Caddyfile)。它把 `/assets` 中的静态文件直接返回，
把上传文件映射到 `/data/assets_cache`，其余请求重写到 `public/index.php` 并通过 FastCGI
连接 `app:9000`。

如果要让 Caddy 自动申请公网证书，可将 `docker/Caddyfile` 中的 `:80` 改为域名，
并确保 80、443 端口可从公网访问。
