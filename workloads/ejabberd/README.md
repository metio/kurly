<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ejabberd

[ejabberd](https://github.com/processone/ejabberd) — a robust, scalable
XMPP/messaging server. A plain composable `kurly.http` workload on the official
community image that keeps its Mnesia database and uploads on a PersistentVolume,
so it needs no external database by default.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ejabberd = import 'github.com/metio/kurly/workloads/ejabberd/server.libsonnet';

kurly.list(ejabberd())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ejabberd` | |
| `image` | `docker.io/ejabberd/ecs:26.04` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the Mnesia database volume |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves XMPP client (`:5222`), server-to-server (`:5269`), and the admin/HTTP API
(`:5280`). Route the XMPP ports as TCP through a LoadBalancer or Gateway TCPRoute,
and expose `:5280` for the admin UI.

## Configuration

ejabberd reads `ejabberd.yml` from `/home/ejabberd/conf`. Mount it with
`kurly.config` (host, admin, listeners); any credentials it references belong in a
Secret (kurly mints none).

## Persistence

The Mnesia database lives on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two pods off the files. Clustering ejabberd
across pods needs shared Mnesia or an external database — beyond this recipe's
default.
