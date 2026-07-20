<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# redis-commander

[Redis Commander](https://github.com/joeferner/redis-commander) — a self-hosted web UI for managing Redis. A **stateless** `kurly.http` workload on the official image (pinned by digest — Renovate maintains it).

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rc = import 'github.com/metio/kurly/workloads/redis-commander/server.libsonnet';
kurly.list(rc(redisHosts='local:redis:6379'))
```

Point it at Redis through `redisHosts` (`REDIS_HOSTS`). Serves on `:8081`.
