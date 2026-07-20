<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# calibre-web-automated

[Calibre-Web Automated](https://github.com/crocodilestick/Calibre-Web-Automated) — a self-hosted web reader and library manager for a Calibre ebook library, adding automatic ingest and format conversion on top of Calibre-Web. A `kurly.http` workload on the LinuxServer.io-based image; application config on one PersistentVolume and the Calibre library on another.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cwa = import 'github.com/metio/kurly/workloads/calibre-web-automated/server.libsonnet';
kurly.list(cwa())
```

Config at `/config` and library at `/calibre-library` on ReadWriteOnce volumes, so **one replica, recreated**. Serves the web app on `:8083`.
