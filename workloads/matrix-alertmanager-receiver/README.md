<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# matrix-alertmanager-receiver

[matrix-alertmanager-receiver](https://github.com/metio/matrix-alertmanager-receiver)
is the webhook receiver an Alertmanager posts to, which forwards each alert into
a Matrix room.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local receiver = import 'github.com/metio/kurly/workloads/matrix-alertmanager-receiver/server.libsonnet';

kurly.list(receiver(
  homeserverUrl='https://matrix.example.com',
  userId='@alerts:matrix.example.com',
  roomMapping={ pager: '!qohfwef7qwerf:example.com' },
))
```

Point an Alertmanager at it by room name:

```yaml
receivers:
  - name: matrix
    webhook_configs:
      - url: "http://matrix-alertmanager-receiver:12345/alerts/pager"
```

Nothing outside the cluster needs to reach it, so an exposure is optional —
compose one only when the Alertmanager posting to it runs elsewhere, and turn on
`basicAuth` when it does.

## Secret

kurly authors no Secret. Provide one named after the workload holding:

| Key | Notes |
| --- | --- |
| `MATRIX_ACCESS_TOKEN` | access token for the posting account |
| `BASIC_PASSWORD` | only when `basicAuth=true` |

The access token is referenced from the configuration file as
`${MATRIX_ACCESS_TOKEN}` and expanded at startup, so it never lands in the
ConfigMap — which anything holding `get` on the namespace can read, and which a
full credential for the posting account has no business being in.

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
metadata: { name: kurly, namespace: matrix-alertmanager-receiver }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-matrix-alertmanager-receiver, namespace: matrix-alertmanager-receiver }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/matrix-alertmanager-receiver, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: matrix-alertmanager-receiver }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-matrix-alertmanager-receiver, namespace: matrix-alertmanager-receiver }
spec: { sourceRef: { kind: OCIRepository, name: kurly-matrix-alertmanager-receiver } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: matrix-alertmanager-receiver, namespace: matrix-alertmanager-receiver }
spec:
  serviceAccountName: matrix-alertmanager-receiver-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/matrix-alertmanager-receiver/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-matrix-alertmanager-receiver, importPath: github.com/metio/kurly/workloads/matrix-alertmanager-receiver }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: matrix-alertmanager-receiver, namespace: matrix-alertmanager-receiver }
spec:
  serviceAccountName: matrix-alertmanager-receiver-deployer
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
        name: matrix-alertmanager-receiver
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: matrix-alertmanager-receiver }
```

<!-- END generated: jaas-deploy -->
