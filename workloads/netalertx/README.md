<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# netalertx

[NetAlertX](https://github.com/jokob-sk/NetAlertX) — scans a network, keeps an
inventory of the devices it finds, and notifies when one appears, disappears or
changes. A plain composable `kurly.http` workload keeping its configuration and
SQLite database on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local netalertx = import 'github.com/metio/kurly/workloads/netalertx/server.libsonnet';

kurly.list(netalertx())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `netalertx` | |
| `image` | `ghcr.io/netalertx/netalertx:26.8.5` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/data` |
| `env` / `resources` / `labels` / `annotations` | | |

## What it can see is the pod's network

This is the thing to decide before deploying, not after. NetAlertX discovers
devices with `arp-scan` and friends, from wherever it is running — and on a CNI
overlay that is the pod subnet. A default deployment therefore inventories other
pods, reaches nothing behind the node, and looks like a broken install while
working exactly as designed.

There are two ways out, and kurly only ships one of them. Where the cluster
already routes to the range in question, point the scan at that range in
`app.conf` (`SCAN_SUBNETS`) and leave the pod where it is — the scanners keep the
raw-socket capabilities they need, because this workload keeps the default
capability set.

The other way is putting the pod on the host's network, which no kurly feature
does: host networking is a property of the pod spec that a consumer patches onto
the rendered Deployment. It is a deliberate step outside the restricted posture —
such a pod shares the node's interfaces and its localhost — so it is a decision to
take on purpose rather than a flag to add.

## Security posture

The entrypoint runs as root, prepares `/data` for its own account and drops to it
with `su-exec`, and the scanning binaries carry file capabilities it must be able
to gain on exec — so `rootUser`, `allowPrivilegeEscalation` and
`keepCapabilities` are all genuinely required. Everything the application writes
outside `/data` the image already points at `/tmp` (the rendered nginx
configuration, the php-fpm and cron run directories, the logs, the API
snapshots), so the root filesystem stays read-only with a `scratch` there.

Service links are disabled: the image's own environment is entirely
`NETALERTX_*`-prefixed, and a Service named `netalertx` makes Kubernetes inject
`NETALERTX_PORT` as a `tcp://` URL into the same namespace of names.

## Persistence

`app.conf` and the SQLite database both live under `/data`, so one volume
persists everything. One SQLite database on a ReadWriteOnce volume, so this is
**one replica, recreated** (never rolled).

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
metadata: { name: kurly, namespace: netalertx }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-netalertx, namespace: netalertx }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/netalertx, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: netalertx }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-netalertx, namespace: netalertx }
spec: { sourceRef: { kind: OCIRepository, name: kurly-netalertx } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: netalertx, namespace: netalertx }
spec:
  serviceAccountName: netalertx-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/netalertx/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-netalertx, importPath: github.com/metio/kurly/workloads/netalertx }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: netalertx, namespace: netalertx }
spec:
  serviceAccountName: netalertx-deployer
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
        name: netalertx
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: netalertx }
```

<!-- END generated: jaas-deploy -->
