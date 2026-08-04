<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# srs

[SRS](https://github.com/ossrs/srs) — Simple Realtime Server, a live streaming
server that ingests RTMP, SRT or WebRTC and delivers HLS, HTTP-FLV and WebRTC. A
plain composable `kurly.http` workload that needs nothing external; the segments
it writes live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local srs = import 'github.com/metio/kurly/workloads/srs/server.libsonnet';

kurly.list(srs())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `srs` | |
| `image` | `ossrs/srs:v6.0.85` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | recorded segments |
| `config` | a starter `srs.conf` | see below before replacing it |
| `candidate` | unset | the address WebRTC players are told to reach |
| `env` / `resources` / `labels` / `annotations` | | |

## Ports, and why only one of them is exposed

HLS and HTTP-FLV are served on `:8080`, which is the port an exposure attaches to:

```jsonnet
kurly.list([
  srs() + kurly.expose.ownGateway('stream.example.com', 'istio', tls='srs-tls'),
  kurly.certificate('srs-tls', ['stream.example.com'], 'letsencrypt-prod'),
])
```

The rest are on the Service but cannot be routed by an Ingress or HTTPRoute,
because none of them is HTTP:

| port | protocol | for |
|---|---|---|
| 1935 | TCP | RTMP ingest |
| 1985 | TCP | the HTTP API |
| 8000 | UDP | WebRTC |
| 10080 | UDP | SRT ingest |

Give them a `TCPRoute`/`UDPRoute` or a `LoadBalancer` Service if publishers and
players are outside the cluster.

**`candidate` matters for WebRTC and nothing else.** WebRTC negotiates an address
for the media connection rather than reusing the one the player asked over, so
that address has to be reachable *by the player*. Unset, SRS resolves it to the
pod address — correct in-cluster, useless from outside.

## The starter configuration is not a convenience

Three lines of the shipped `config` are what make SRS run as a container at all,
and replacing it without them produces a workload that never stays up:

- **`daemon off`** — the image's own `conf/srs.conf` says `daemon on`, so SRS
  forks and the process the container was started for exits. Kubernetes restarts
  it, forever.
- **`srs_log_tank console`** — the default writes to a log file inside the image
  that nobody will read.
- **`pid /tmp/srs.pid`** — the default is `./objs/srs.pid`, inside the install
  tree, which is read-only here. It cannot simply be given a volume either:
  `objs/` also holds the `srs` binary and would be shadowed by one.

The file is mounted as a single file over the shipped `conf/srs.conf`, leaving the
rest of `conf/` in place, so the image's own command finds it without anything
overriding the command.

## Persistence

Recorded segments and HLS playlists live on one ReadWriteOnce volume, so this is
**one replica, recreated** (never rolled) to keep two pods off the files. `/` on
:8080 answers 404 until something is published — the web root *is* the segment
directory — which is why health here is a connection check rather than a page.

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
metadata: { name: kurly, namespace: srs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-srs, namespace: srs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/srs, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: srs }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-srs, namespace: srs }
spec: { sourceRef: { kind: OCIRepository, name: kurly-srs } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: srs, namespace: srs }
spec:
  serviceAccountName: srs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/srs/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-srs, importPath: github.com/metio/kurly/workloads/srs }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: srs, namespace: srs }
spec:
  serviceAccountName: srs-deployer
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
        name: srs
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: srs }
```

<!-- END generated: jaas-deploy -->
