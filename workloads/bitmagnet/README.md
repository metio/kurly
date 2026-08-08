<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bitmagnet

[bitmagnet](https://bitmagnet.io) — a BitTorrent indexer that crawls the DHT,
classifies what it finds and serves it as a searchable catalogue with a web UI,
a GraphQL API and Torznab endpoints for the Servarr stack. A composable
`kurly.http` workload backed by an external PostgreSQL and holding no state of
its own.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local bitmagnet = import 'github.com/metio/kurly/workloads/bitmagnet/server.libsonnet';

kurly.list(bitmagnet())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `bitmagnet` | |
| `image` | `ghcr.io/bitmagnet-io/bitmagnet:v0.10.0` | |
| `keys` | `http_server`, `queue_server`, `dht_crawler` | the services the worker runs |
| `dbHost` / `dbPort` / `database` / `dbUser` | `bitmagnet-db-rw` … | pairs with a `cnpg-cluster` named `bitmagnet-db` |
| `secretName` | `bitmagnet` | holds `POSTGRES_PASSWORD` |

## Supply the Secret

Upstream's compose file publishes the password `postgres`. Supplying this is the
difference between a database only this workload can reach and one anybody who
has read the repository can.

```shell
kubectl create secret generic bitmagnet \
  --from-literal=POSTGRES_PASSWORD=…
```

## Crawling needs egress

The DHT crawler speaks to the swarm on `:3334`, TCP and UDP both, and that port
rides onto the Service beside the web port. It needs **unrestricted egress** to
arbitrary internet hosts on arbitrary UDP ports: a NetworkPolicy that allows
only PostgreSQL leaves the index permanently empty, and the pod stays perfectly
healthy while it happens. Drop `dht_crawler` from `keys` to serve an index
without adding to it.

## Persistence

Everything the crawler collects is in PostgreSQL, so this workload claims no
volume — point `dbHost` at one that is backed up, and expect it to **grow**: an
indexer indexes for as long as it runs.

## Metadata lookups

Content classification enriches from TMDB when an API key is present. Add
`TMDB_API_KEY` through `env` (or the Secret) if you want it; without one the
classifier falls back to what it can read off the torrent itself.

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
metadata: { name: kurly, namespace: bitmagnet }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-bitmagnet, namespace: bitmagnet }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/bitmagnet, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: bitmagnet }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-bitmagnet, namespace: bitmagnet }
spec: { sourceRef: { kind: OCIRepository, name: kurly-bitmagnet } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: bitmagnet, namespace: bitmagnet }
spec:
  serviceAccountName: bitmagnet-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/bitmagnet/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-bitmagnet, importPath: github.com/metio/kurly/workloads/bitmagnet }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: bitmagnet, namespace: bitmagnet }
spec:
  serviceAccountName: bitmagnet-deployer
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
        name: bitmagnet
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: bitmagnet }
```

<!-- END generated: jaas-deploy -->
