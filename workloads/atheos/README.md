<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# atheos

[Atheos](https://www.atheos.io) — a web-based IDE with a small footprint,
continued from Codiad. A plain composable `kurly.http` workload on the
maintainer's [Apache/PHP image](https://hub.docker.com/r/hlsiira/atheos), with its
whole install tree on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local atheos = import 'github.com/metio/kurly/workloads/atheos/server.libsonnet';

kurly.list(atheos())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `atheos` | |
| `image` | `docker.io/hlsiira/atheos:latest` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the install tree (`/var/www/html`) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the IDE on `:80` — compose an exposure onto it.

## Finish the installer before anyone else can

A fresh instance answers with its **install page**, and whoever reaches it first
creates the account that owns the editor and everything it can write. Roll it out,
finish the installer yourself, and only then point anyone at it — or put an
authenticating proxy in front. There is nothing in this workload that can decide
it for you.

## State and first boot

Atheos keeps **no database**: users, projects and sessions live in `data/`, edited
files in `workspace/`, and the installer writes `config.php` next to the code — one
tree, all of it state, so the volume is the whole document root.

A PersistentVolume arrives empty and would hide the application the image ships. A
Docker named volume is seeded from the image on first use and Kubernetes does no
such thing, so an init container mounts the same volume elsewhere and copies the
image's tree in when it finds no `index.php`. With one present the copy is skipped,
so an installed instance's `config.php`, users and workspace are never overwritten.
The first start therefore takes a while, which is what the startup probe budgets
for.

## Security and persistence

Apache starts as **root** to bind `:80` and drops its workers to `www-data`, so this
workload relaxes kurly's non-root default and grants back only the capabilities that
change identity and reach the files `www-data` owns. Apache and PHP write their pid
files, sockets, logs and sessions outside the volume, so the root filesystem is
writable. The tree lives on a ReadWriteOnce volume, so this is **one replica,
recreated** — two pods editing the same files is not something the IDE reconciles
afterwards.

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
metadata: { name: kurly, namespace: atheos }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-atheos, namespace: atheos }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/atheos, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: atheos }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-atheos, namespace: atheos }
spec: { sourceRef: { kind: OCIRepository, name: kurly-atheos } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: atheos, namespace: atheos }
spec:
  serviceAccountName: atheos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/atheos/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-atheos, importPath: github.com/metio/kurly/workloads/atheos }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: atheos, namespace: atheos }
spec:
  serviceAccountName: atheos-deployer
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
        name: atheos
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: atheos }
```

<!-- END generated: jaas-deploy -->
