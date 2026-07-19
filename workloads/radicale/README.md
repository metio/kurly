<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# radicale

[Radicale](https://radicale.org/) — a lightweight CalDAV and CardDAV server for
calendars and contacts. A plain composable `kurly.http` workload on the
well-maintained [tomsquest](https://github.com/tomsquest/docker-radicale) image
that keeps its collections on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local radicale = import 'github.com/metio/kurly/workloads/radicale/server.libsonnet';

kurly.list(radicale())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `radicale` | |
| `image` | `docker.io/tomsquest/docker-radicale:3.7.6.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the collections volume (`/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves CalDAV/CardDAV on `:5232` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  radicale()
  + kurly.expose.ownGateway('dav.example.com', 'istio', tls='radicale-tls'),
  kurly.certificate('radicale-tls', ['dav.example.com'], 'letsencrypt-prod'),
])
```

## Authentication

The default configuration allows **anonymous access**. For real use, mount a
Radicale config and an htpasswd users file (a Secret — kurly mints none) and set
`auth` to `htpasswd`:

```jsonnet
radicale()
+ kurly.config('/config', { config: '[auth]\ntype = htpasswd\nhtpasswd_filename = /config/users\nhtpasswd_encryption = bcrypt\n' })
+ kurly.secretMount('radicale-users', '/config/users-secret')
```

## Security and persistence

The image runs its s6 init as its designated **uid 2999** and writes to the root
filesystem, so this workload pins that uid and relaxes the read-only-rootfs default
while keeping non-root, dropped capabilities, and no privilege escalation. The
collections live on a ReadWriteOnce volume, so this is **one replica, recreated**.
