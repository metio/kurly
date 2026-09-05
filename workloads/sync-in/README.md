<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# sync-in

[Sync-in](https://github.com/Sync-in/server) — file storage, syncing and sharing
with real-time collaboration and per-space permission management, plus desktop
and web clients. A composable `kurly.http` workload backed by an external
MySQL/MariaDB, with the files themselves on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local syncin = import 'github.com/metio/kurly/workloads/sync-in/server.libsonnet';

kurly.list(syncin())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `sync-in` | |
| `image` | `docker.io/syncin/server:2.5.0` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/app/data` |
| `secretName` | `sync-in` | four credentials, see below |
| `env` | `{}` | any `SYNCIN_…` override |

## Configuration is environment variables, not a document

The server reads `environment/environment.yaml` and then overlays every
`SYNCIN_`-prefixed variable whose dotted path exists in the configuration model
it ships — `SYNCIN_MYSQL_URL` sets `mysql.url`,
`SYNCIN_AUTH_TOKEN_ACCESS_SECRET` sets `auth.token.access.secret`. Nothing has to
be authored as a file, so anything the workload does not set can be added through
`env` (mail, LDAP, OIDC, an external Redis for cache and websockets). A path the
model does not know is logged as ignored rather than applied, which is worth
reading the startup log for once.

Two settings are made here because the image's own defaults are wrong for a pod:
`applications.files.dataPath` ships as `/home/sync-in`, which is not where the
volume is mounted, and the listen address and port are stated explicitly so the
declared container port cannot drift from the one the process binds.

## Supply the Secret

Every one of these has a published placeholder in the project's compose file, the
token secrets included.

| key | what it is |
|---|---|
| `SYNCIN_MYSQL_URL` | `mysql://user:pass@host:3306/sync_in` |
| `SYNCIN_AUTH_ENCRYPTIONKEY` | encrypts user secrets (MFA seeds) in the database |
| `SYNCIN_AUTH_TOKEN_ACCESS_SECRET` | signs access tokens and cookies |
| `SYNCIN_AUTH_TOKEN_REFRESH_SECRET` | signs refresh tokens |

```shell
kubectl create secret generic sync-in \
  --from-literal=SYNCIN_MYSQL_URL='mysql://sync_in:…@sync-in-db:3306/sync_in' \
  --from-literal=SYNCIN_AUTH_ENCRYPTIONKEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=SYNCIN_AUTH_TOKEN_ACCESS_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=SYNCIN_AUTH_TOKEN_REFRESH_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

Do not change `SYNCIN_AUTH_ENCRYPTIONKEY` after anyone has enabled MFA — the
stored seeds are encrypted with it and become unreadable.

Adding `INIT_ADMIN`, `INIT_ADMIN_LOGIN` and `INIT_ADMIN_PASSWORD` to the same
Secret makes the first start create the administrator account; the run marks
itself done afterwards and never repeats it.

## The first start migrates

Before it listens, the server waits for the database and runs the schema
migrations, so it has a startup probe rather than a generous liveness delay. It
probes by connection: every HTTP path either redirects to the login page or
answers 401, and a probe following either kills the pod for good.

The cache defaults to the MySQL adapter, which tries to turn the server's event
scheduler on and needs `SUPER` to do it. On a managed database the grant is
usually absent, the attempt is logged as an error, and the server falls back to
its own scheduler — the message is expected, not a failure. Point
`SYNCIN_CACHE_ADAPTER` and `SYNCIN_CACHE_REDIS` at a Redis to avoid it.

## Less hardened, deliberately

The entrypoint creates the account named by `PUID`/`PGID`, chowns the data volume
and drops to it with `su-exec`, which it can only do starting from root, so
non-root, privilege escalation and dropped capabilities are relaxed. The root
filesystem is writable because the completed first run is recorded as
`/app/.init`, beside the application's own code.

## Persistence

Personal and shared spaces live on a ReadWriteOnce volume, so this is **one
replica, recreated** (never rolled). Metadata, accounts and permissions are in
MySQL — point `SYNCIN_MYSQL_URL` at one that is backed up, and back up the volume
with it: neither half is useful alone.

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
metadata: { name: kurly, namespace: sync-in }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-sync-in, namespace: sync-in }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/sync-in, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: sync-in }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-sync-in, namespace: sync-in }
spec: { sourceRef: { kind: OCIRepository, name: kurly-sync-in } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: sync-in, namespace: sync-in }
spec:
  serviceAccountName: sync-in-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/sync-in/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-sync-in, importPath: github.com/metio/kurly/workloads/sync-in }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: sync-in, namespace: sync-in }
spec:
  serviceAccountName: sync-in-deployer
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
        name: sync-in
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: sync-in }
```

<!-- END generated: jaas-deploy -->
