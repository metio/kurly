<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# neko

[neko](https://github.com/m1k1o/neko) — a virtual browser running inside the
container, its screen and sound streamed to everyone in the room over WebRTC,
with shared control of the mouse and keyboard. A plain composable `kurly.http`
workload on the official Firefox image.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local neko = import 'github.com/metio/kurly/workloads/neko/server.libsonnet';

kurly.list(neko(nat1to1='203.0.113.10'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `neko` | |
| `image` | `ghcr.io/m1k1o/neko/firefox:3.1.5` | |
| `secretName` | `neko` | Secret with the two multiuser passwords (`envFrom`) |
| `webrtcPort` | `59000` | one port, multiplexed on TCP **and** UDP |
| `nat1to1` | — | the address clients reach `webrtcPort` on |
| `screen` | `1280x720@30` | the virtual screen the browser draws on |
| `shmSize` | `1Gi` | `/dev/shm` scratch for decoded frames |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the room UI and the signalling WebSocket on `:8080` — compose an exposure
onto it.

## The media path is not the exposure

Only signalling goes through the Ingress or HTTPRoute; the screen and sound are
WebRTC. Both transports are multiplexed onto `webrtcPort`, so one port has to be
reachable from the client on TCP and UDP — and `nat1to1` has to name the address
it is reachable on, because the candidate the pod would otherwise advertise is its
own, which no browser can route to. Without it the room loads, the password is
accepted, and the screen never arrives.

## Auth

The multiuser member provider takes two passwords, one for watching and one for
administering the room. kurly authors **no Secret** — provide `neko` holding
`NEKO_MEMBER_MULTIUSER_USER_PASSWORD` and `NEKO_MEMBER_MULTIUSER_ADMIN_PASSWORD`,
pulled in via `envFrom`.

## Posture

Deliberately less hardened than most workloads here. `supervisord` starts as root
to bring up the X server, D-Bus and PulseAudio before dropping each program to the
`neko` account, so it needs root, the capabilities that account switch uses, and
privilege escalation. The browser profile lives in `/home/neko` among files the
image ships, so nothing can be mounted there without hiding them and the root
filesystem is writable instead.

Nothing is kept between restarts: a room is a browser session, so this claims no
PersistentVolume and runs **one replica**, recreated — a second replica would be a
second, unrelated room behind one address.

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
metadata: { name: kurly, namespace: neko }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-neko, namespace: neko }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/neko, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: neko }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-neko, namespace: neko }
spec: { sourceRef: { kind: OCIRepository, name: kurly-neko } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: neko, namespace: neko }
spec:
  serviceAccountName: neko-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/neko/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-neko, importPath: github.com/metio/kurly/workloads/neko }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: neko, namespace: neko }
spec:
  serviceAccountName: neko-deployer
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
        name: neko
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: neko }
```

<!-- END generated: jaas-deploy -->
