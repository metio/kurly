<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# peer-calls

[Peer Calls](https://peercalls.com) — group video calls in the browser over
WebRTC, peer-to-peer or relayed through the server's own SFU. A plain composable
`kurly.http` workload: nothing is written down, so it needs no database and no
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local peercalls = import 'github.com/metio/kurly/workloads/peer-calls/server.libsonnet';

kurly.list(peercalls())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `peer-calls` | |
| `image` | the pinned upstream image | |
| `replicas` | `1` | only raise this alongside `redisHost` |
| `redisHost` / `redisPort` | none / `6379` | the Redis signalling state is shared through |
| `env` | `{}` | any other `PEERCALLS_*` setting |
| `resources` / `labels` / `annotations` | | |

Serves the web app and the signalling WebSocket on `:3000` — compose an exposure
onto it. TLS is not optional in practice: a browser will not hand a page its
camera or microphone unless the page came over HTTPS.

## Replicas

Signalling state lives in the process, so two pods answering the same room do not
see each other's peers and the call silently splits. Keep one replica unless
`redisHost` names a Redis for Peer Calls to share that state through.

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
metadata: { name: kurly, namespace: peer-calls }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-peer-calls, namespace: peer-calls }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/peer-calls, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: peer-calls }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-peer-calls, namespace: peer-calls }
spec: { sourceRef: { kind: OCIRepository, name: kurly-peer-calls } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: peer-calls, namespace: peer-calls }
spec:
  serviceAccountName: peer-calls-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/peer-calls/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-peer-calls, importPath: github.com/metio/kurly/workloads/peer-calls }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: peer-calls, namespace: peer-calls }
spec:
  serviceAccountName: peer-calls-deployer
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
        name: peer-calls
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: peer-calls }
```

<!-- END generated: jaas-deploy -->
