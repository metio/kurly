<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# your-spotify

[Your Spotify](https://github.com/Yooooomi/your_spotify) — a self-hosted dashboard of
your own Spotify listening history and statistics. A plain composable `kurly.http`
workload on the official server image, backed by an external MongoDB.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local yourSpotify = import 'github.com/metio/kurly/workloads/your-spotify/server.libsonnet';

kurly.list(yourSpotify(
  apiEndpoint='https://spotify-api.example.com',
  clientEndpoint='https://spotify.example.com',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `your-spotify` | |
| `image` | `docker.io/yooooomi/your_spotify_server` | |
| `replicas` | `2` | stateless — scale freely |
| `apiEndpoint` | unset | the public URL of this server |
| `clientEndpoint` | unset | the public URL of the web client |
| `secretName` | `your-spotify` | Secret with `MONGO_ENDPOINT`, `SPOTIFY_PUBLIC`, `SPOTIFY_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the API on `:8080` — compose an exposure onto it. It needs a MongoDB you
provide; `MONGO_ENDPOINT` in the Secret is the whole connection string.

Both endpoints are public URLs a browser resolves: the Spotify OAuth redirect is built
from `apiEndpoint`, so it must match the redirect URI registered on the Spotify
application whose id and secret the Secret carries. The web client is a separate image
and is not carried here.

## Persistence

Every scrobble the server records lands in MongoDB, so this is **stateless** — a plain
rolling Deployment.

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
metadata: { name: kurly, namespace: your-spotify }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-your-spotify, namespace: your-spotify }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/your-spotify, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: your-spotify }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-your-spotify, namespace: your-spotify }
spec: { sourceRef: { kind: OCIRepository, name: kurly-your-spotify } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: your-spotify, namespace: your-spotify }
spec:
  serviceAccountName: your-spotify-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/your-spotify/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-your-spotify, importPath: github.com/metio/kurly/workloads/your-spotify }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: your-spotify, namespace: your-spotify }
spec:
  serviceAccountName: your-spotify-deployer
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
        name: your-spotify
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: your-spotify }
```

<!-- END generated: jaas-deploy -->
