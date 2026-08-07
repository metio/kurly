<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# downtify

[Downtify](https://github.com/henriquesebastiao/downtify) — paste a Spotify
track, album or playlist link and it finds the audio on YouTube Music, converts
it with ffmpeg and writes it out with album art and metadata attached. A plain
composable `kurly.http` workload with two PersistentVolumes and no external
service of any kind.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local downtify = import 'github.com/metio/kurly/workloads/downtify/server.libsonnet';

kurly.list(downtify())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `downtify` | |
| `image` | `ghcr.io/henriquesebastiao/downtify:2.9.1` | |
| `mediaSize` | `100Gi` | the music library (`/downloads`) |
| `storageSize` | `1Gi` | settings and the monitor database (`/data`) |
| `storageClass` | cluster default | both volumes |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8000`:

```jsonnet
kurly.list([
  downtify()
  + kurly.expose.ownGateway('music.example.com', 'istio', tls='downtify-tls'),
  kurly.certificate('downtify-tls', ['music.example.com'], 'letsencrypt-prod'),
])
```

There is no authentication in front of it — anyone who reaches the UI can queue
downloads, browse the library and delete from it. Put an authenticating proxy in
front if it is reachable from anywhere untrusted.

## No account, no key, no external service

Spotify is only ever read as a public page, and the audio comes from YouTube
Music, so nothing has to be registered and no credential has to be minted: this
workload reads no Secret. What it does need is egress to the public internet,
which a default-deny NetworkPolicy takes away — compose `kurly.network.*` with
the egress it needs rather than discovering it as downloads that never start.

## Two volumes, sized very differently

`/data` is settings plus the small SQLite database behind playlist monitoring,
and is roughly fixed. `/downloads` is the music, and is the half that grows
without limit. They are separate parameters so the expensive one can be sized —
and given a different storage class — without dragging the other with it.

## Probing

There is no health endpoint, so the probes read `/api/version`: it answers
unauthenticated and touches neither disk nor network. The single-page app at `/`
would be the obvious choice and is the wrong one — it is a static file behind
whatever rewrite or redirect sits in front of it, which would then decide the
pod's fate instead of the application.

## Persistence

Files and one SQLite database on ReadWriteOnce volumes, so this is **one
replica, recreated** (never rolled) — which keeps two pods off the library and,
just as importantly, two schedulers off the same monitored playlists, where the
second one downloads every new track a second time.

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
metadata: { name: kurly, namespace: downtify }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-downtify, namespace: downtify }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/downtify, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: downtify }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-downtify, namespace: downtify }
spec: { sourceRef: { kind: OCIRepository, name: kurly-downtify } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: downtify, namespace: downtify }
spec:
  serviceAccountName: downtify-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/downtify/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-downtify, importPath: github.com/metio/kurly/workloads/downtify }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: downtify, namespace: downtify }
spec:
  serviceAccountName: downtify-deployer
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
        name: downtify
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: downtify }
```

<!-- END generated: jaas-deploy -->
