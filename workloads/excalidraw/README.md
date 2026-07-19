<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# excalidraw

[Excalidraw](https://github.com/excalidraw/excalidraw) — a virtual hand-drawn-style
whiteboard. A plain composable `kurly.http` workload on the official image.
Excalidraw is a client-side app: the container just serves the static assets and
drawings live in the browser, so this workload is **stateless** and can run several
replicas.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local excalidraw = import 'github.com/metio/kurly/workloads/excalidraw/server.libsonnet';

kurly.list(excalidraw())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `excalidraw` | |
| `image` | `docker.io/excalidraw/excalidraw:sha-4bfc5bb` | immutable sha tag (no semver published) |
| `replicas` | `1` | stateless — scale out freely |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the app on `:80` — compose an exposure onto it.

## Security

The nginx image serving the static assets starts as **root** and binds `:80`, so
this workload relaxes kurly's non-root and read-only-rootfs defaults while keeping
dropped capabilities and no privilege escalation.
