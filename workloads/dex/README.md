<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# dex

[Dex](https://dexidp.io/) — an OpenID Connect / OAuth 2.0 identity provider that
federates to upstream connectors (LDAP, SAML, GitHub, Google, …). A plain composable
`kurly.http` workload on the official image: with the SQLite storage backend its
state lives on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dex = import 'github.com/metio/kurly/workloads/dex/server.libsonnet';

kurly.list(dex())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `dex` | |
| `image` | `ghcr.io/dexidp/dex:v2.45.1` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite state (`/var/dex`) |
| `configSecret` | `dex-config` | Secret holding `config.yaml`, mounted at `/etc/dex` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the OIDC endpoints on `:5556` — compose an exposure onto it.

## Configuration

Dex is entirely driven by a `config.yaml` (issuer, storage, connectors,
`staticClients`). It carries secrets (client secrets, connector credentials), so
mount it from a Secret — kurly authors **none** — at `/etc/dex`. The default storage
is SQLite on the volume; point it at PostgreSQL in the config to scale past the single
writer, or use the `kubernetes` storage backend composed with `kurly.rbac`.

## Persistence

With SQLite storage, the database lives on a ReadWriteOnce volume, so this is **one
replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/).
