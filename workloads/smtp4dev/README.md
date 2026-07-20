<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# smtp4dev

[smtp4dev](https://github.com/rnwood/smtp4dev) — a self-hosted fake SMTP server for development: it receives the mail your apps send and shows it in a web UI, without delivering anything onward. A `kurly.http` workload on the official image, listening on **two ports** (the web UI and the SMTP sink) via `kurly.extraPort`; message database on a PersistentVolume under `/smtp4dev`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local smtp4dev = import 'github.com/metio/kurly/workloads/smtp4dev/server.libsonnet';
kurly.list(smtp4dev())
```

Database at `/smtp4dev` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the web UI on `:80` and accepts SMTP on `:25` — point your apps' SMTP client at the Service on port 25, and compose an exposure onto the web port.
