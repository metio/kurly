<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# meshmonitor

[MeshMonitor](https://meshmonitor.org/) — a web front end for a Meshtastic mesh:
it connects to a node over TCP, records the messages, telemetry and node list it
sees, and draws them on a map and a timeline. A plain composable `kurly.http`
workload: everything it knows goes into a SQLite database on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local meshmonitor = import 'github.com/metio/kurly/workloads/meshmonitor/server.libsonnet';

kurly.list(meshmonitor(nodeIp='10.0.0.42'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `meshmonitor` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | database, backups, notification config (`/data`) |
| `nodeIp` / `nodePort` | none / `4403` | the Meshtastic node to connect to |
| `behindProxy` | `true` | secure cookies and a trusted forwarded address |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:3001` — compose an exposure onto it.

## It needs a node it can reach over IP

Meshtastic radios are usually attached to a device by USB or Bluetooth, neither of
which a pod can be given. `nodeIp` is the address of a node with the TCP API
enabled — an ESP32 node on WiFi, or a host running a Meshtastic daemon. Egress
from the cluster to that address is a prerequisite, and it is the first thing to
check when the UI comes up empty.

## Running it unprivileged

The image's supervisord declares `user=root` and drops to the `node` user with
`su-exec`, which normally means a root container. It does not here: the runtime
uid is set to the `node` user's own 1000, so the `su-exec` call is a change to the
uid the process already has, and the entrypoint explicitly skips its `chown` when
it is not root because `fsGroup` has already done that job. supervisord's pidfile
lives in `/var/run`, which is a scratch volume, so the root filesystem stays
read-only.

Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
recreated.

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
metadata: { name: kurly, namespace: meshmonitor }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-meshmonitor, namespace: meshmonitor }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/meshmonitor, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: meshmonitor }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-meshmonitor, namespace: meshmonitor }
spec: { sourceRef: { kind: OCIRepository, name: kurly-meshmonitor } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: meshmonitor, namespace: meshmonitor }
spec:
  serviceAccountName: meshmonitor-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/meshmonitor/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-meshmonitor, importPath: github.com/metio/kurly/workloads/meshmonitor }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: meshmonitor, namespace: meshmonitor }
spec:
  serviceAccountName: meshmonitor-deployer
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
        name: meshmonitor
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: meshmonitor }
```

<!-- END generated: jaas-deploy -->
