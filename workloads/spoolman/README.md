<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# spoolman

[Spoolman](https://github.com/Donkie/Spoolman) — keeps track of 3D-printing
filament: which spools you own, what is left on each, and what got used by which
print. A plain composable `kurly.http` workload whose SQLite database lives on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local spoolman = import 'github.com/metio/kurly/workloads/spoolman/server.libsonnet';

kurly.list(spoolman())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `spoolman` | |
| `image` | `ghcr.io/donkie/spoolman:0.26.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/data` |
| `env` | `{}` | any `SPOOLMAN_*` setting, including `SPOOLMAN_DB_TYPE` |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and REST API on `:8000`:

```jsonnet
kurly.list([
  spoolman()
  + kurly.expose.ownGateway('spools.example.com', 'istio', tls='spoolman-tls'),
  kurly.certificate('spoolman-tls', ['spools.example.com'], 'letsencrypt-prod'),
])
```

## No authentication, by design

Printers and slicers talk to the REST API with **no credential** — that is what
makes the integration simple, and it means exposing this is a decision rather than
a default. Keep it on the network your printers are on, or put something
authenticating in front of it.

## `SPOOLMAN_DIR_DATA`

The image's default data directory is a path under the app account's home
directory: sensible for a desktop install, awkward to mount a volume over. This
workload points it at `/data` instead, which is where the volume mounts.

Pointing `SPOOLMAN_DB_TYPE` and friends at PostgreSQL through `env` moves the
database off the volume entirely.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled).

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
metadata: { name: kurly, namespace: spoolman }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-spoolman, namespace: spoolman }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/spoolman, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: spoolman }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-spoolman, namespace: spoolman }
spec: { sourceRef: { kind: OCIRepository, name: kurly-spoolman } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: spoolman, namespace: spoolman }
spec:
  serviceAccountName: spoolman-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/spoolman/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-spoolman, importPath: github.com/metio/kurly/workloads/spoolman }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: spoolman, namespace: spoolman }
spec:
  serviceAccountName: spoolman-deployer
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
        name: spoolman
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: spoolman }
```

<!-- END generated: jaas-deploy -->
