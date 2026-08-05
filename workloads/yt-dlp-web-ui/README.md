<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# yt-dlp-web-ui

[yt-dlp Web UI](https://github.com/marcopiovanello/yt-dlp-web-ui) — a browser front
end for yt-dlp. Paste a URL, pick a format, watch the progress, fetch the file. A
plain composable `kurly.http` workload; downloads land on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ytdlp = import 'github.com/metio/kurly/workloads/yt-dlp-web-ui/server.libsonnet';

kurly.list(ytdlp())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `yt-dlp-web-ui` | |
| `image` | `ghcr.io/marcopiovanello/yt-dlp-web-ui:v3.0.0` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | `/downloads` |
| `env` / `resources` / `labels` / `annotations` | | |

## Think about this one before exposing it

It downloads **whatever it is asked to, from wherever the pod can reach**, and has
no authentication unless you configure one. An instance reachable from the internet
is an open downloader running inside your network — useful to somebody else, and
attributable to you.

Two things worth pairing with it:

```jsonnet
// an authenticating proxy in front, and a policy that bounds where it can go
ytdlp() + kurly.network.kubernetes(allowTo=[{ cidr: '0.0.0.0/0', ports: [443] }])
```

The egress question is the one people forget: the pod can reach whatever the
cluster lets it reach, including things on your internal network that have nothing
to do with video.

## Persistence

Downloads land on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled). The image's own entrypoint already passes `--out /downloads`, so
the volume mounts there and no argument is overridden. Size it for what you intend
to keep — this is the only thing here that grows.

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
metadata: { name: kurly, namespace: yt-dlp-web-ui }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-yt-dlp-web-ui, namespace: yt-dlp-web-ui }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/yt-dlp-web-ui, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: yt-dlp-web-ui }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-yt-dlp-web-ui, namespace: yt-dlp-web-ui }
spec: { sourceRef: { kind: OCIRepository, name: kurly-yt-dlp-web-ui } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: yt-dlp-web-ui, namespace: yt-dlp-web-ui }
spec:
  serviceAccountName: yt-dlp-web-ui-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/yt-dlp-web-ui/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-yt-dlp-web-ui, importPath: github.com/metio/kurly/workloads/yt-dlp-web-ui }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: yt-dlp-web-ui, namespace: yt-dlp-web-ui }
spec:
  serviceAccountName: yt-dlp-web-ui-deployer
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
        name: yt-dlp-web-ui
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: yt-dlp-web-ui }
```

<!-- END generated: jaas-deploy -->
