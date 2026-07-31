<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# owntracks-recorder

[OwnTracks Recorder](https://github.com/owntracks/recorder) — a self-hosted store and web UI for the location data your OwnTracks phone apps publish. A `kurly.http` workload on the official image; the location store on a PersistentVolume under `/store`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local recorder = import 'github.com/metio/kurly/workloads/owntracks-recorder/server.libsonnet';
kurly.list(recorder())
```

Store at `/store` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the UI and HTTP recorder endpoint on `:8083`. The phone apps can publish over HTTP directly, or via an MQTT broker the Recorder subscribes to (`OTR_HOST`/`OTR_PORT`).

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
metadata: { name: kurly, namespace: owntracks-recorder }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-owntracks-recorder, namespace: owntracks-recorder }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/owntracks-recorder, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: owntracks-recorder }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-owntracks-recorder, namespace: owntracks-recorder }
spec: { sourceRef: { kind: OCIRepository, name: kurly-owntracks-recorder } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: owntracks-recorder, namespace: owntracks-recorder }
spec:
  serviceAccountName: owntracks-recorder-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/owntracks-recorder/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-owntracks-recorder, importPath: github.com/metio/kurly/workloads/owntracks-recorder }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: owntracks-recorder, namespace: owntracks-recorder }
spec:
  serviceAccountName: owntracks-recorder-deployer
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
        name: owntracks-recorder
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: owntracks-recorder }
```

<!-- END generated: jaas-deploy -->
