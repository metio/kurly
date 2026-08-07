<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# imgcompress

[imgcompress](https://github.com/karimz1/imgcompress) — compresses, converts,
resizes and batch-processes images through a web interface, including
HEIC/WebP/PDF conversion and background removal that runs locally rather than in
somebody else's cloud. A plain composable `kurly.http` workload.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local imgcompress = import 'github.com/metio/kurly/workloads/imgcompress/server.libsonnet';

kurly.list(imgcompress())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `imgcompress` | |
| `image` | `karimz1/imgcompress:0.8.3` | |
| `tempSize` | `4Gi` | the scratch volume at `/tmp` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and its API on `:5000` — compose an exposure onto it.

## Nothing is persisted

Uploads and results live in a temporary directory the application sweeps an hour
after they were written. There is no PersistentVolume here and nothing to back
up: a restart loses whatever a user has not downloaded yet.

That directory is the one thing worth sizing. It holds every uploaded image and
every rendered output at once, and the application accepts a 40 GiB upload by
default, so `tempSize` is the real cap on what a single batch may cost the node.
It is a scratch volume rather than the container filesystem, which keeps a large
batch from filling the node's image store.

## One replica

A download link names the temporary folder the run wrote, and only the pod that
made it can serve those files back. A second replica would answer roughly half
the downloads with a 404, so this is deliberately one.

## Security

The image runs as its own unprivileged account (65532) with no shell, so nothing
about privileges is relaxed. The root filesystem is writable for a single
reason: the entrypoint writes the frontend's `runtime.json` into the image's own
tree before the server starts, and that path is too long to name a volume after
(a volume name is a DNS label, and it is 69 characters), so it cannot be carved
out the way `/tmp` is.

Background removal and format conversion are CPU work on data a user just
uploaded — the CPU limit is what stops one large batch starving its neighbours.

There is **no authentication**. Anyone who can reach it can spend the CPU and the
scratch volume, so put an authenticating proxy in front of an instance reachable
from the internet.

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
metadata: { name: kurly, namespace: imgcompress }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-imgcompress, namespace: imgcompress }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/imgcompress, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: imgcompress }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-imgcompress, namespace: imgcompress }
spec: { sourceRef: { kind: OCIRepository, name: kurly-imgcompress } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: imgcompress, namespace: imgcompress }
spec:
  serviceAccountName: imgcompress-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/imgcompress/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-imgcompress, importPath: github.com/metio/kurly/workloads/imgcompress }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: imgcompress, namespace: imgcompress }
spec:
  serviceAccountName: imgcompress-deployer
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
        name: imgcompress
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: imgcompress }
```

<!-- END generated: jaas-deploy -->
