<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mediamtx

[MediaMTX](https://mediamtx.org) — a real-time media server and proxy: it ingests a live stream over one protocol and republishes it over the others. A `kurly.http` workload on the official image; its only state is the `mediamtx.yml` it starts from, rendered as a ConfigMap and passed as the server's argument.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mediamtx = import 'github.com/metio/kurly/workloads/mediamtx/server.libsonnet';
kurly.list(mediamtx())
```

The HTTP port is **HLS on `:8888`** — the one an Ingress or HTTPRoute can carry, so compose an exposure onto it for browser playback. Everything else is published beside it on the Service and is not HTTP: **RTSP `:8554`** (with the RTP/RTCP pair `:8000`/`:8001` UDP the UDP transport uses), **RTMP `:1935`**, **WebRTC `:8889`** with its ICE mux on `:8189` UDP, **SRT `:8890`** UDP. Route those with a LoadBalancer; an HTTP proxy cannot. The control API serves on `:9997` and Prometheus metrics on `:9998`.

**WebRTC needs a candidate address a browser can reach.** The pod IP is not one, so a deployment that publishes WebRTC beyond the cluster sets `webrtcAdditionalHosts` in `config` to the address its LoadBalancer answers on. HLS playback has no such requirement.

`config` is the whole `mediamtx.yml`; replace or extend it for authentication, named paths, or an on-demand source. **No Secret, and no authentication either**: as it stands anybody who reaches a port can publish and read streams — decide that before exposing it. MoQ is disabled because it would bind two further ports over a certificate it mints for itself.

Nothing is written to disk, so there is no PersistentVolume. Streams are per-connection rather than shared, so a second replica is a second server with its own streams, not a bigger one. Compose `kurly.store` and set the record options in `config` to keep recordings.

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
metadata: { name: kurly, namespace: mediamtx }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mediamtx, namespace: mediamtx }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mediamtx, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mediamtx }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mediamtx, namespace: mediamtx }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mediamtx } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mediamtx, namespace: mediamtx }
spec:
  serviceAccountName: mediamtx-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mediamtx/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mediamtx, importPath: github.com/metio/kurly/workloads/mediamtx }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mediamtx, namespace: mediamtx }
spec:
  serviceAccountName: mediamtx-deployer
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
        name: mediamtx
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mediamtx }
```

<!-- END generated: jaas-deploy -->
