<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# apprise

[Apprise](https://github.com/caronc/apprise) — a self-hosted push-notification relay that fans one request out to 100+ services (email, Slack, Telegram, ntfy, webhooks, and more). A `kurly.http` workload on the official image; persistent named notification configs on a PersistentVolume under `/config`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local apprise = import 'github.com/metio/kurly/workloads/apprise/server.libsonnet';
kurly.list(apprise())
```

Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the API on `:8000`. It can also run stateless (POST with inline URLs) — drop the store if you never persist named configs.
