<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# element-web

[Element Web](https://github.com/element-hq/element-web) — the popular self-hosted web client for the Matrix network. A **stateless** `kurly.http` workload on the official image; its `config.json` is mounted into the web root via a **subPath** ConfigMap mount, beside the app's own files.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local element = import 'github.com/metio/kurly/workloads/element-web/server.libsonnet';
kurly.list(element(homeserverUrl='https://matrix.example.com', serverName='example.com'))
```

Element is a client only — point it at a Matrix homeserver (e.g. [matrix-conduit](../matrix-conduit/)) via `homeserverUrl`/`serverName`. Pass `config` to override or extend Element's `config.json` verbatim. Serves on `:80`.
