<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tube-archivist

[Tube Archivist](https://github.com/tubearchivist/tubearchivist) — subscribe to
YouTube channels and playlists, download what they publish, and serve the result
as your own media library: searchable, with metadata, artwork and playback
progress. A composable `kurly.http` workload with two PersistentVolumes and two
external dependencies.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tubearchivist = import 'github.com/metio/kurly/workloads/tube-archivist/server.libsonnet';

kurly.list(tubearchivist(taHost='https://tube.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `tube-archivist` | |
| `image` | `docker.io/bbilly1/tubearchivist:v0.5.10` | |
| `taHost` | unset | the public origin, protocol included |
| `mediaSize` / `storageSize` / `storageClass` | `500Gi` / `10Gi` / cluster default | `/youtube`, `/cache` |
| `esUrl` | `http://tube-archivist-es:9200` | Elasticsearch 8 |
| `redisCon` | `redis://tube-archivist-redis:6379` | |
| `timezone` | `UTC` | the scheduler's timezone |
| `secretName` | `tube-archivist` | see below |
| `env` / `resources` / `labels` / `annotations` | | |

## It needs Elasticsearch and Redis

Neither is rendered here and neither is optional: everything the archive knows is
indexed in **Elasticsearch 8**, and every download, scan and refresh runs through
a **Redis**-backed task queue. The `opensearch-cluster` workload is not a
substitute — Tube Archivist talks to Elasticsearch through the official client,
which refuses a server that does not identify as Elasticsearch.

## `taHost` decides whether anything works

Django checks the origin of every request against `TA_HOST` and answers a
mismatch with a bare `400`. There is no sane default for it, so it is left unset
and the application refuses to start until you supply the URL you actually reach
the instance at — a placeholder would turn a configuration mistake into what
looks like a broken image.

## The Secret

`secretName` supplies the initial administrator and the Elasticsearch credential
through `envFrom`. `TA_USERNAME` / `TA_PASSWORD` are read once, when the account
is created; changing them afterwards does nothing, and the account is changed
from inside the application.

```shell
kubectl create secret generic tube-archivist \
  --from-literal=TA_USERNAME=admin \
  --from-literal=TA_PASSWORD="$(head -c 24 /dev/urandom | base64)" \
  --from-literal=ELASTIC_PASSWORD="$(head -c 24 /dev/urandom | base64)"
```

## It needs egress, which is easy to forget

Downloading is the entire point: the pod reaches YouTube and the yt-dlp release
feed. A NetworkPolicy written from the shape of the manifest blocks that, and the
failure is quiet — the UI loads, subscriptions save, and nothing ever downloads.

## Persistence and hardening

Artwork, thumbnails and yt-dlp state live at `/cache`; the videos at `/youtube`,
which is the half that grows without limit. Both are ReadWriteOnce, so this is
**one replica, recreated** — also because two schedulers would fetch the same
videos twice.

The image selects no account and its nginx is configured to run as root, so this
workload runs as root with a writable root filesystem (collectstatic writes the
built assets beside the code, nginx wants `/var/lib/nginx` and `/run`). Nothing
escalates privileges, so the capability set stays dropped. Probes are by
connection, because every path answers a redirect or a 403 to an unauthenticated
request.

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
metadata: { name: kurly, namespace: tube-archivist }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-tube-archivist, namespace: tube-archivist }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tube-archivist, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tube-archivist }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-tube-archivist, namespace: tube-archivist }
spec: { sourceRef: { kind: OCIRepository, name: kurly-tube-archivist } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tube-archivist, namespace: tube-archivist }
spec:
  serviceAccountName: tube-archivist-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/tube-archivist/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-tube-archivist, importPath: github.com/metio/kurly/workloads/tube-archivist }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tube-archivist, namespace: tube-archivist }
spec:
  serviceAccountName: tube-archivist-deployer
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
        name: tube-archivist
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: tube-archivist }
```

<!-- END generated: jaas-deploy -->
