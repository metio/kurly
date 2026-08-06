<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# koillection

[Koillection](https://github.com/benjaminjonard/koillection) — a collection
manager: whatever you collect, described with the fields you decide it has, plus
wishlists, loans and a tag index. A composable `kurly.http` workload backed by an
external PostgreSQL, with uploaded images on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local koillection = import 'github.com/metio/kurly/workloads/koillection/server.libsonnet';

kurly.list(koillection())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `koillection` | |
| `image` | `docker.io/benjaminjonard/koillection:1.5.15` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | mounted at `/uploads` |
| `dbHost` / `dbPort` / `database` / `dbUser` / `dbVersion` | `koillection-db-rw` … | pairs with a `cnpg-cluster` named `koillection-db` |
| `corsAllowOrigin` | localhost only | which origins the JSON API answers |
| `uploadMaxFilesize` | `100M` | PHP and nginx are set together |
| `httpsEnabled` | `true` | sets `session.cookie_secure` |
| `secretName` | `koillection` | three credentials, see below |

## Supply the Secret

```shell
kubectl create secret generic koillection \
  --from-literal=DB_PASSWORD=… \
  --from-literal=APP_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=JWT_PASSPHRASE="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

The entrypoint invents `APP_SECRET` and `JWT_PASSPHRASE` with `openssl rand` when
they are unset. That reads as a safe default and is not one: a fresh value is
generated on every start, so every session and every API token is invalidated
whenever the pod is rescheduled, and a JWT keypair on the read-write layer does
not survive it either.

`httpsEnabled` defaults to true because that is what an exposed deployment does.
Behind plain HTTP the browser discards the session cookie and nobody can log in —
set it to false only for a local test.

## Less hardened, deliberately

The entrypoint runs `usermod`/`groupmod`, chowns `/uploads` to the resolved
`PUID`/`PGID` and starts php-fpm and nginx, all of which need root, and nginx
binds `:80`. The root filesystem is writable because the application writes
inside its own tree: the generated `.env.local`, the Symfony cache and logs, the
JWT keypair, and the php-fpm and nginx runtime files.

## Persistence

Uploaded images live on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). Everything else is in PostgreSQL — point `dbHost` at
one that is backed up. The database migration runs at every start, before nginx
binds, which is why the startup probe allows five minutes.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

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
metadata: { name: kurly, namespace: koillection }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-koillection, namespace: koillection }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/koillection, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: koillection }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-koillection, namespace: koillection }
spec: { sourceRef: { kind: OCIRepository, name: kurly-koillection } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: koillection, namespace: koillection }
spec:
  serviceAccountName: koillection-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/koillection/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-koillection, importPath: github.com/metio/kurly/workloads/koillection }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: koillection, namespace: koillection }
spec:
  serviceAccountName: koillection-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: koillection
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: koillection }
```

<!-- END generated: jaas-deploy -->
