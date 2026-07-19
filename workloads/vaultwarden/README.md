<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# vaultwarden

[Vaultwarden](https://github.com/dani-garcia/vaultwarden) — a lightweight,
Bitwarden-compatible password manager written in Rust. A plain composable
`kurly.http` workload that keeps its vault, attachments, and JWT signing key in a
**SQLite database on a PersistentVolume**, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local vaultwarden = import 'github.com/metio/kurly/workloads/vaultwarden/server.libsonnet';

kurly.list(vaultwarden(domain='https://vault.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `vaultwarden` | |
| `image` | `docker.io/vaultwarden/server:1.36.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite DB, attachments, and JWT key |
| `domain` | inferred | **the public URL** — WebAuthn, attachments, and email need it |
| `signupsAllowed` | `false` | new-user registration |
| `env` | `{}` | extra Vaultwarden settings — see below |
| `resources` / `labels` / `annotations` | | |

Serves the web vault and API on `:8080` (moved off the image's default `:80` so a
non-root pod can bind it). Compose an exposure and a certificate onto it:

```jsonnet
kurly.listOf([
  vaultwarden(domain='https://vault.example.com')
  + kurly.expose.ownGateway('vault.example.com', 'istio', tls='vault-tls'),
  kurly.certificate('vault-tls', ['vault.example.com'], 'letsencrypt-prod'),
])
```

**Set `domain`** to the URL clients actually reach it at — WebAuthn/passkeys,
attachment links, and email all embed it, and they misbehave when it's wrong.

## Registration and the admin panel

`signupsAllowed` is **off** by default — a password manager open to the world is
rarely what you want. Turn it on to create the first account, then off. To invite
users instead, enable the admin panel by setting `ADMIN_TOKEN` through `env` — a
secret, so provide it from a Secret rather than a literal:

```jsonnet
vaultwarden(env={ ADMIN_TOKEN: '...' })   // better: sourced from a Secret
```

kurly authors no Secret, so the admin token (and any external-DB password) are
yours to provide — fill them from your secrets store with `kurly.externalSecret`.

## Persistence and scale

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two pods off the file — the same single-writer
discipline as [tik](../tik/) and [forgejo](../forgejo/). The JWT signing key lives
on that volume, so sessions survive restarts.

To scale past a single writer, point `DATABASE_URL` at an external **PostgreSQL**
through `env` (pairs with the [cnpg-cluster](../cnpg-cluster/) workload); the
connection string then carries a password, so build it from a Secret.
