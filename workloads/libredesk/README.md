<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# libredesk

[Libredesk](https://github.com/abhinavxd/libredesk) — a self-hosted customer
support desk: shared inboxes, conversations, assignment rules, canned responses
and SLAs, in one binary. A composable `kurly.http` workload backed by an external
PostgreSQL.

It claims **no PersistentVolume**: conversations, users and settings all live in
the database, so the database is the thing to back up.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local libredesk = import 'github.com/metio/kurly/workloads/libredesk/server.libsonnet';

kurly.list(libredesk(appUrl='https://support.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `libredesk` | |
| `image` | `ghcr.io/abhinavxd/libredesk:v2.6.1` | |
| `dbHost` / `dbPort` / `database` / `dbUser` | `libredesk-db-rw` … | pairs with a `cnpg-cluster` named `libredesk-db` |
| `appUrl` | unset | the public URL |
| `secretName` | `libredesk` | supplies `LIBREDESK_DB__PASSWORD` |

## The environment names follow config.toml's sections, not a guess

Libredesk maps environment variables onto its `config.toml`, and the database
table is **top-level `[db]`**, not `[app.db]`:

```text
LIBREDESK_DB__HOST      ✓
LIBREDESK_APP__DB__HOST ✗ — ignored, no error
```

That distinction is worth stating because getting it wrong is silent: unmatched
variables are ignored, the file's own defaults stand, and the server tries to
reach a PostgreSQL literally called `db` — a DNS failure for a host nobody
configured.

## Two init containers, not one

`--install --idempotent-install` lays the schema down at v0.0.0 and skips if one
already exists. That is not enough on its own: the server then refuses to start
with

```text
there are 16 pending database upgrade(s) ... run libredesk --upgrade
```

so `--upgrade` runs as a second init step. Both are idempotent, which is what
makes them safe on every start rather than a one-off somebody has to remember at
the worst moment.

## Persistence

None of its own. Point `dbHost` at a PostgreSQL that is backed up — the
[cnpg-cluster](../cnpg-cluster/) workload provides one, and
[volsync](../volsync/) or [k8up](../k8up/) can take it off the cluster.

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
metadata: { name: kurly, namespace: libredesk }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-libredesk, namespace: libredesk }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/libredesk, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: libredesk }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-libredesk, namespace: libredesk }
spec: { sourceRef: { kind: OCIRepository, name: kurly-libredesk } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: libredesk, namespace: libredesk }
spec:
  serviceAccountName: libredesk-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/libredesk/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-libredesk, importPath: github.com/metio/kurly/workloads/libredesk }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: libredesk, namespace: libredesk }
spec:
  serviceAccountName: libredesk-deployer
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
        name: libredesk
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: libredesk }
```

<!-- END generated: jaas-deploy -->
