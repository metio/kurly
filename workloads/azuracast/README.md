<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# azuracast

[AzuraCast](https://github.com/AzuraCast/AzuraCast) — runs an internet radio
station: a media library, playlists and schedules, live DJ sessions, and the
Icecast/Liquidsoap stack that actually broadcasts them. A composable
`kurly.http` workload on the official all-in-one image, backed by an external
MariaDB and an external Redis, with the station media library on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local azuracast = import 'github.com/metio/kurly/workloads/azuracast/server.libsonnet';

kurly.list(azuracast())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `azuracast` | |
| `image` | `ghcr.io/azuracast/azuracast:stable` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | `/var/azuracast/stations` |
| `dbHost` / `dbPort` / `database` / `dbUser` | `azuracast-db` … | pairs with a `mysql-cluster` named `azuracast-db` |
| `redisHost` / `redisPort` / `redisDatabase` | `azuracast-cache` … | sessions, cache and the queue |
| `stationPorts` | `2` | broadcast ports published from 8000 up |
| `secretName` | `azuracast` | holds `MYSQL_PASSWORD` |

## Two ways in, and only one of them is HTTP

The web app, the API and the station player are on `:80` — compose an exposure
onto it. Each station **also** broadcasts on its own TCP port, allocated from
8000 upwards, and that is a raw stream rather than HTTP: an Ingress or an
HTTPRoute will not carry it. `stationPorts` decides how many of those ports the
Service publishes; a station whose port is not on the Service is audible inside
the pod and nowhere else. Reaching listeners from outside needs a TCP route (a
Gateway TCPRoute, or a LoadBalancer Service) pointed at those ports.

## Supply the Secret and the two backing services

AzuraCast keeps its configuration, users and station definitions in MariaDB, and
uses Redis for sessions, caching and the message queue that drives playlists.
Neither is optional and neither is in this image.

```shell
kubectl create secret generic azuracast \
  --from-literal=MYSQL_PASSWORD=…
```

## Less hardened, deliberately

`supervisord` starts nginx, php-fpm, Liquidsoap and Icecast together and drops
privileges to their own accounts, which it can only do starting from root, and
the entrypoint chowns the media tree on the volume. The root filesystem is
writable because php-fpm, nginx and Liquidsoap keep sockets, caches and logs
inside the image's own tree.

## Persistence

Only `/var/azuracast/stations` is mounted — `/var/azuracast` also holds the
application itself, and a volume over the whole directory hides it. The media
library is a ReadWriteOnce volume, so this is **one replica, recreated** (never
rolled). Everything else is in MariaDB — point `dbHost` at one that is backed
up.

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
metadata: { name: kurly, namespace: azuracast }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-azuracast, namespace: azuracast }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/azuracast, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: azuracast }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-azuracast, namespace: azuracast }
spec: { sourceRef: { kind: OCIRepository, name: kurly-azuracast } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: azuracast, namespace: azuracast }
spec:
  serviceAccountName: azuracast-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/azuracast/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-azuracast, importPath: github.com/metio/kurly/workloads/azuracast }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: azuracast, namespace: azuracast }
spec:
  serviceAccountName: azuracast-deployer
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
        name: azuracast
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: azuracast }
```

<!-- END generated: jaas-deploy -->
