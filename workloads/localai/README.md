<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# localai

[LocalAI](https://github.com/mudler/LocalAI) — an OpenAI-compatible API in front
of language, image and audio models that run on your own hardware. A plain
composable `kurly.http` workload on the official CPU image: models, downloaded
backends and generated content live on a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local localai = import 'github.com/metio/kurly/workloads/localai/server.libsonnet';

kurly.list(localai())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `localai` | |
| `image` | `docker.io/localai/localai:v4.8.2` | the CPU image |
| `storageSize` / `storageClass` | `50Gi` / cluster default | models and backends |
| `secretName` | `null` | envFrom source for `LOCALAI_API_KEY` and friends |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the OpenAI-compatible API and the web UI on `:8080` — compose an exposure
onto it.

## Models and access

No model ships in the image. Pull one at runtime through the UI or the models
endpoint, or preload one through the environment; the first pull downloads
gigabytes onto the volume, so size it for what you intend to run. Inference here
is on the CPU — a GPU needs one of upstream's accelerator images plus the
matching device resources.

The API is **unauthenticated** until `LOCALAI_API_KEY` is set. kurly authors no
Secret: create one holding the key and name it in `secretName`, and do not put
this on a public host without it.

## Persistence

Models and backends live on a ReadWriteOnce volume, so this is **one replica,
recreated** — the same single-writer discipline as
[audiobookshelf](../audiobookshelf/).

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
metadata: { name: kurly, namespace: localai }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-localai, namespace: localai }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/localai, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: localai }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-localai, namespace: localai }
spec: { sourceRef: { kind: OCIRepository, name: kurly-localai } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: localai, namespace: localai }
spec:
  serviceAccountName: localai-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/localai/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-localai, importPath: github.com/metio/kurly/workloads/localai }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: localai, namespace: localai }
spec:
  serviceAccountName: localai-deployer
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
        name: localai
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: localai }
```

<!-- END generated: jaas-deploy -->
