<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mirumoji

[Mirumoji](https://github.com/svdC1/mirumoji) — a Japanese immersion toolkit: it
tokenises the subtitles of a video, makes every word clickable for a dictionary
lookup with a kanji breakdown, transcribes audio and exports flashcards. A plain
composable `kurly.http` workload keeping its media, profiles and SQLite database
on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mirumoji = import 'github.com/metio/kurly/workloads/mirumoji/server.libsonnet';

kurly.list(mirumoji())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mirumoji` | |
| `image` | `docker.io/svdc1/mirumoji:backend-cpu-3.7.2` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/root/.local/share/mirumoji` |
| `transcribeBackend` | `auto` | `auto`, `local` or `modal` |
| `logLevel` | `INFO` | |
| `secretName` | none | the optional API keys, see below |
| `env` / `resources` / `labels` / `annotations` | | |

## This is the backend, not the frontend

Upstream ships two images and starts both from one compose file. This workload
carries the **backend** — the FastAPI server that does the tokenising, the
lookups and the transcription. The React frontend image is not carried: it
terminates TLS itself with a certificate authority it mints at runtime and hands
out for each device to install, which is exactly the job an Ingress or an
HTTPRoute already does in a cluster. Point a browser client at this API and let
the cluster's own exposure hold the certificate.

## It needs no egress until you ask for it

The dictionary data is baked into the image — UniDic in `site-packages`, and the
Kotobase databases, which are half a gigabyte on their own. Nothing is downloaded
at start, so subtitles, lookups and flashcards all work on a pod with no route
off the cluster at all.

Egress is only needed for the two optional features: an LLM provider for sentence
breakdowns and subtitle refinement, and [Modal](https://modal.com) for offloading
transcription to a rented GPU. Both are switched on by supplying their keys.

## The Secret

Every key in it is optional, which is why `secretName` defaults to none:

```shell
kubectl create secret generic mirumoji \
  --from-literal=OPENAI_API_KEY=… \
  --from-literal=MODAL_TOKEN_ID=… \
  --from-literal=MODAL_TOKEN_SECRET=…
```

`ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `MIRUMOJI_LLM_API_KEY` and
`MIRUMOJI_LLM_BASE_URL` are read from the same Secret; the last two are how an
OpenAI-compatible endpoint of your own is used instead.

## Why it runs as root

Unusual here, and deliberate. The server resolves its storage through
`platformdirs` under `$HOME`, and the dictionary databases the image bakes in sit
in root's home directory at mode `0700` — an unprivileged account cannot even
traverse into it, so the very lookups a fresh install exists to answer would all
fail. The root filesystem stays read-only (Kotobase opens its databases read-only)
and no capability or privilege escalation is granted.

## Persistence

One SQLite database, plus uploaded media and generated clips, on a ReadWriteOnce
volume — so this is **one replica, recreated** (never rolled). Media is what makes
the volume grow; `20Gi` is a starting point, not a limit anyone measured.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

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
metadata: { name: kurly, namespace: mirumoji }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mirumoji, namespace: mirumoji }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mirumoji, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mirumoji }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mirumoji, namespace: mirumoji }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mirumoji } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mirumoji, namespace: mirumoji }
spec:
  serviceAccountName: mirumoji-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mirumoji/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mirumoji, importPath: github.com/metio/kurly/workloads/mirumoji }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mirumoji, namespace: mirumoji }
spec:
  serviceAccountName: mirumoji-deployer
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
        name: mirumoji
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mirumoji }
```

<!-- END generated: jaas-deploy -->
