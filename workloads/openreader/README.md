<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# openreader

[OpenReader](https://github.com/richardr1126/openreader) — a text-to-speech
reader for EPUB, PDF, Markdown, plain text and DOCX documents: it reads a
document aloud and highlights the words as they are spoken. A plain composable
`kurly.http` workload with no external dependency — the image carries its own
SQLite database, an embedded SeaweedFS blob store and an embedded NATS
JetStream, all under one directory on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local openreader = import 'github.com/metio/kurly/workloads/openreader/server.libsonnet';

kurly.list(openreader(baseUrl='https://read.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `openreader` | |
| `image` | `ghcr.io/richardr1126/openreader:4.4.0` | |
| `baseUrl` | `https://openreader.example.com` | a placeholder — see below |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/app/docstore` |
| `apiBase` | unset | the TTS endpoint, seeded on first boot only |
| `secretName` | `openreader` | `AUTH_SECRET`, optionally `API_KEY` |
| `adminEmails` | unset | comma-separated |

## `baseUrl` has no usable default

Uploads and downloads are **presigned**: the browser is handed a URL and fetches
the blob store directly. Both those URLs and the session cookies are minted
against `BASE_URL`, so an instance left on the placeholder authenticates nobody
and stores nothing. Pass the address users actually reach.

For the same reason the Service publishes **two** ports: `:3003` for the app and
`:8333` for the embedded SeaweedFS S3 endpoint. An exposure that routes only the
app leaves a reader that lists documents it cannot open.

## Supply the Secret

```shell
kubectl create secret generic openreader \
  --from-literal=AUTH_SECRET="$(openssl rand -base64 32)"
```

Add `API_KEY` to the same Secret if the TTS provider `apiBase` points at wants
one. Both `apiBase` and `API_KEY` are read **once**, on the first boot, to seed
the default provider; afterwards providers are administered from Settings →
Admin, so changing them later moves nothing.

## Speech is not in the image

OpenReader renders and aligns the text itself, but the voice comes from a TTS
service you point it at — a self-hosted one (Kokoro-FastAPI, KittenTTS-FastAPI,
Orpheus-FastAPI) or a cloud API. Without one the reader works and stays silent.

## Persistence

The metadata database, the uploaded documents and the broker state share one
ReadWriteOnce volume, so this is **one replica, recreated** (never rolled). It
runs as the `node` account the image ships (uid 1000) with the hardened defaults
intact; `fsGroup` hands it the volume.

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
metadata: { name: kurly, namespace: openreader }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-openreader, namespace: openreader }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/openreader, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: openreader }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-openreader, namespace: openreader }
spec: { sourceRef: { kind: OCIRepository, name: kurly-openreader } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: openreader, namespace: openreader }
spec:
  serviceAccountName: openreader-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/openreader/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-openreader, importPath: github.com/metio/kurly/workloads/openreader }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: openreader, namespace: openreader }
spec:
  serviceAccountName: openreader-deployer
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
        name: openreader
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: openreader }
```

<!-- END generated: jaas-deploy -->
