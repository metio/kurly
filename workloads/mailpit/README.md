<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mailpit

[Mailpit](https://mailpit.axllent.org) — a self-hosted email- and SMTP-testing tool: it catches every message your apps send and shows them in a web UI, with a real SMTP sink and an API. A `kurly.http` workload on the official image, listening on **two ports** (the web UI/API and the SMTP sink) via `kurly.extraPort`; message store (SQLite) on a PersistentVolume under `/data`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mailpit = import 'github.com/metio/kurly/workloads/mailpit/server.libsonnet';
kurly.list(mailpit())
```

Store at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the web UI and API on `:8025` and accepts SMTP on `:1025` — point your apps' SMTP client at the Service on port 1025, and compose an exposure onto the web port.
