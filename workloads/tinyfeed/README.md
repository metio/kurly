<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tinyfeed

[tinyfeed](https://github.com/TheBigRoomXXL/tinyfeed) — a CLI that reads a list
of RSS, Atom and JSON feeds and writes one static HTML page aggregating them. A
plain composable `kurly.worker` workload running the CLI in its daemon mode, so
the page is rewritten on an interval, onto a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tinyfeed = import 'github.com/metio/kurly/workloads/tinyfeed/generator.libsonnet';

kurly.list(tinyfeed(feeds=[
  'https://lovergne.dev/rss.xml',
  'https://tonsky.me/atom.xml',
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `tinyfeed` | |
| `image` | `docker.io/thebigroomxxl/tinyfeed:v1.5.0` | |
| `feeds` | the project's release feed | one URL per entry, rendered to the input file |
| `storageSize` / `storageClass` / `accessModes` | `1Gi` / cluster default / `ReadWriteOnce` | `/output` |
| `outputPath` | `/output/index.html` | the page the HTTP server serves |
| `interval` | `1440` | minutes between regenerations |
| `title` / `description` | `Feed` / none | the page heading and the line under it |
| `stylesheet` / `script` / `template` | none | links on the page; `template` is a path inside the container |
| `limit` / `limitPerFeed` | `256` / `256` | articles shown |
| `extraArgs` | `[]` | appended verbatim after the flags above |
| `env` / `resources` / `labels` / `annotations` | | merged over the defaults |

## There is no server here

tinyfeed is a static site generator. It binds no port and answers no request, so
this is a worker with no Service and nothing to compose an exposure onto — it
writes one file and sleeps until the next interval.

Serving that file is a **second workload**: an HTTP server mounting the same
claim read-only, with the exposure on it. kurly's `caddy` workload is one such
server. Two pods reading one claim need a class supporting `ReadWriteMany`, or
both pods scheduled onto the same node; `accessModes` is a parameter for exactly
that reason.

## The feed list is the workload

`feeds` is rendered to `feeds.txt` in a ConfigMap mounted at `/etc/tinyfeed`, and
the CLI reads it with `--input`. Changing which feeds are aggregated is therefore
a re-render, not an exec into a running pod. Comment lines starting with `#` are
allowed, so an entry may carry a section heading.

Everything else tinyfeed accepts is a flag. The common ones are parameters;
anything not listed goes through `extraArgs` verbatim (`--order-by`, `--requests`,
`--timeout`, `--quiet`).

## Persistence

One file on a ReadWriteOnce volume by default, so this is **one replica,
recreated** (never rolled). A second replica would write the same file from two
processes, which is not a form of redundancy.

## Posture

The image is `FROM scratch` around one static Go binary with a non-root `USER`:
no shell, no entrypoint dropping privileges, nothing written outside the volume.
It keeps the fully restricted default — non-root, read-only root filesystem, all
capabilities dropped, its own user namespace.

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
metadata: { name: kurly, namespace: tinyfeed }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-tinyfeed, namespace: tinyfeed }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tinyfeed, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tinyfeed }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-tinyfeed, namespace: tinyfeed }
spec: { sourceRef: { kind: OCIRepository, name: kurly-tinyfeed } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tinyfeed, namespace: tinyfeed }
spec:
  serviceAccountName: tinyfeed-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local generator = import 'github.com/metio/kurly/workloads/tinyfeed/generator.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(generator())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-tinyfeed, importPath: github.com/metio/kurly/workloads/tinyfeed }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tinyfeed, namespace: tinyfeed }
spec:
  serviceAccountName: tinyfeed-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: generator
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: tinyfeed
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: tinyfeed }
```

<!-- END generated: jaas-deploy -->
