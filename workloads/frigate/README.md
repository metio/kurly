<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# frigate

[Frigate](https://frigate.video) — a self-hosted NVR with real-time object detection. A single
`kurly.http` workload that keeps its config and SQLite database on one volume and recordings on
another, decodes camera frames through a shared-memory scratch, and serves an authenticated UI on
`:8971`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local frigate = import 'github.com/metio/kurly/workloads/frigate/server.libsonnet';

kurly.list([
  frigate()
  + kurly.expose.ownGateway('frigate.example.com', 'istio', tls='frigate-tls'),
  kurly.certificate('frigate-tls', ['frigate.example.com'], 'letsencrypt-prod'),
])
```

## Configuration

Frigate reads `/config/config.yml`. This recipe ships a **minimal starter config** (MQTT off, a
CPU detector, no cameras) mounted read-only over the `/config` volume — replace it with your own
cameras and detectors through the `config` parameter. Because the file is mounted from a ConfigMap,
Frigate's built-in config editor is disabled; to manage config in the UI instead, drop the `config`
parameter and seed `config.yml` onto the volume yourself.

Config and the SQLite database live on `/config`; recordings and clips on `/media`. Both are
ReadWriteOnce volumes, so this is **one replica, recreated**. `FRIGATE_RTSP_PASSWORD` (and any other
secret) comes from `secretName` (`frigate-secrets`) — kurly authors **no Secret**.

## Shared memory and cache

Decoded frames land in an emptyDir scratch at `/dev/shm` (`shmSize`, default `256Mi`) and recording
segments stage in one at `/tmp/cache` (`cacheSize`). **Size `/dev/shm` for your camera count** — the
default suits a couple of 720p streams; too small and the decoder aborts with a bus error. The
scratch is disk-backed; a memory-backed `/dev/shm` (an `emptyDir` with `medium: Memory`) is faster
for many cameras and can be grafted on with the raw `+` escape hatch.

## Ports and hardware

The **authenticated** UI/API is on `:8971` (the port to expose). The plain UI/API stays in-cluster
on `5000`, the RTSP restream on `8554`, and WebRTC two-way audio on `8555` (TCP and UDP).

The default runs **CPU detection**, which the restricted-relaxed posture (root, writable root
filesystem) supports out of the box. A hardware detector — a Coral TPU (`/dev/bus/usb`,
`/dev/apex_0`), a GPU (`/dev/dri/renderD128`) — needs device mounts and the privileges your cluster
requires; add those with the raw `+` escape hatch, since they are the cluster's to grant.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage. Delivered end to end through Flux, JaaS and stageset-controller on 2026-07-31, and observed rolling out.

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
metadata: { name: kurly, namespace: frigate }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-frigate, namespace: frigate }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/frigate, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: frigate }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-frigate, namespace: frigate }
spec: { sourceRef: { kind: OCIRepository, name: kurly-frigate } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: frigate, namespace: frigate }
spec:
  serviceAccountName: frigate-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/frigate/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-frigate, importPath: github.com/metio/kurly/workloads/frigate }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: frigate, namespace: frigate }
spec:
  serviceAccountName: frigate-deployer
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
        name: frigate
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: frigate }
```

<!-- END generated: jaas-deploy -->
