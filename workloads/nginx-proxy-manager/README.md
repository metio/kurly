<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nginx-proxy-manager

[Nginx Proxy Manager](https://nginxproxymanager.com) — a self-hosted reverse-proxy with a web UI, free Let's Encrypt certificates, access lists and custom nginx config. A `kurly.http` workload on the official image; SQLite database and config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local npm = import 'github.com/metio/kurly/workloads/nginx-proxy-manager/server.libsonnet';
kurly.list(npm())
```

The reverse proxy listens on `:80`/`:443` — add a Service (usually a LoadBalancer) for them. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. The admin UI serves on `:81`.
