<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wiki-go

[Wiki-Go](https://github.com/leomoon-studios/wiki-go) — a flat-file wiki written
in Go, where every page is a Markdown file on disk and there is no database at
all. A plain composable `kurly.http` workload; pages, uploads and the wiki's own
generated `config.yaml` live together on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wikigo = import 'github.com/metio/kurly/workloads/wiki-go/server.libsonnet';

kurly.list(wikigo())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wiki-go` | |
| `image` | `leomoonstudios/wiki-go:1.8.12` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the data directory (`/wiki/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the wiki on `:8080` — compose an exposure onto it:

```jsonnet
kurly.list([
  wikigo()
  + kurly.expose.ownGateway('wiki.example.com', 'istio', tls='wiki-go-tls'),
  kurly.certificate('wiki-go-tls', ['wiki.example.com'], 'letsencrypt-prod'),
])
```

## Change the administrator before you publish it

Wiki-Go writes its configuration on first start with a **default administrator
account**, documented in the open. An instance reachable from the internet is
therefore administrable by anyone who read that documentation until you change
it. Log in and replace the account — and decide whether anonymous reading stays
on — before exposing the wiki. Nothing in this workload can decide it for you.

## Persistence

One directory tree on a ReadWriteOnce volume — pages, uploaded files and
`config.yaml` in the same place — so this is **one replica, recreated** (never
rolled) to keep two pods off the same files, the same single-writer discipline as
[otterwiki](../otterwiki/).

The container runs as uid 1000 with a matching `fsGroup`, so the volume is
writable while the rest of the filesystem stays read-only.

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
metadata: { name: kurly, namespace: wiki-go }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wiki-go, namespace: wiki-go }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wiki-go, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wiki-go }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wiki-go, namespace: wiki-go }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wiki-go } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wiki-go, namespace: wiki-go }
spec:
  serviceAccountName: wiki-go-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wiki-go/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wiki-go, importPath: github.com/metio/kurly/workloads/wiki-go }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wiki-go, namespace: wiki-go }
spec:
  serviceAccountName: wiki-go-deployer
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
        name: wiki-go
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wiki-go }
```

<!-- END generated: jaas-deploy -->
