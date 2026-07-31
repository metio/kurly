<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pairdrop

[PairDrop](https://github.com/schlagmichdoch/PairDrop) — a self-hosted, AirDrop-style
local file-sharing app: transfer files and messages between devices over the browser,
peer-to-peer via WebRTC. A plain composable `kurly.http` workload on the official image;
the server only brokers peer connections and keeps no state.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pairdrop = import 'github.com/metio/kurly/workloads/pairdrop/server.libsonnet';
kurly.list(pairdrop())
```

Runs as **one replica** — peers pair through in-memory rooms held by a single server
instance, so more than one replica without sticky routing would split rooms across pods.
Serves on `:3000`.

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
metadata: { name: kurly, namespace: pairdrop }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pairdrop, namespace: pairdrop }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pairdrop, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pairdrop }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pairdrop, namespace: pairdrop }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pairdrop } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pairdrop, namespace: pairdrop }
spec:
  serviceAccountName: pairdrop-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pairdrop/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pairdrop, importPath: github.com/metio/kurly/workloads/pairdrop }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pairdrop, namespace: pairdrop }
spec:
  serviceAccountName: pairdrop-deployer
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
        name: pairdrop
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pairdrop }
```

<!-- END generated: jaas-deploy -->
