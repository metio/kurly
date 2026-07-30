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
| `image` | `docker.io/vaultwarden/server:1.37.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite DB, attachments, and JWT key |
| `domain` | inferred | **the public URL** — WebAuthn, attachments, and email need it |
| `signupsAllowed` | `false` | new-user registration |
| `env` | `{}` | extra Vaultwarden settings — see below |
| `resources` / `labels` / `annotations` | | |

Serves the web vault and API on `:8080` (moved off the image's default `:80` so a
non-root pod can bind it). Compose an exposure and a certificate onto it:

```jsonnet
kurly.list([
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

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**delivered** — this workload is delivered end to end on a live cluster through the real production path — its source image pulled by Flux, rendered by JaaS, applied by stageset-controller — and observed rolling out, on top of its smoke coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: vaultwarden }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-vaultwarden, namespace: vaultwarden }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/vaultwarden, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: vaultwarden }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-vaultwarden, namespace: vaultwarden }
spec: { sourceRef: { kind: OCIRepository, name: kurly-vaultwarden } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: vaultwarden, namespace: vaultwarden }
spec:
  serviceAccountName: vaultwarden-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/vaultwarden/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-vaultwarden, importPath: github.com/metio/kurly/workloads/vaultwarden }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: vaultwarden, namespace: vaultwarden }
spec:
  serviceAccountName: vaultwarden-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: vaultwarden
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: vaultwarden }
```

<!-- END generated: jaas-deploy -->
