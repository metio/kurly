<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lancache

[LanCache](https://lancache.net) monolithic — a caching proxy for game
downloads on a local network. The first machine to download a title pulls it
from the internet; every machine after it reads the same bytes off the local
disk. A plain composable `kurly.http` workload keeping its cache and logs on
PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local lancache = import 'github.com/metio/kurly/workloads/lancache/server.libsonnet';

kurly.list(lancache())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `lancache` | |
| `image` | `docker.io/lancachenet/monolithic:latest` | |
| `cacheSize` / `storageClass` | `50Gi` / cluster default | `/data/cache` |
| `cacheDiskSize` / `minFreeDisk` | `45g` / `5g` | what nginx believes it may fill |
| `cacheMaxAge` / `cacheSliceSize` | `3560d` / `1m` | upstream defaults |
| `logsSize` | `2Gi` | `/data/logs` |
| `upstreamDns` | `8.8.8.8 8.8.4.4` | where misses are resolved |
| `timezone` / `env` / `resources` / `labels` / `annotations` | | |

## DNS is the half that is not here

A cache only sees a download if the client resolves the content-delivery
hostname to this pod's address. That is a resolver's job — the monolithic image
caches, it does not answer DNS. Run something that does ([blocky](../blocky),
[pihole](../pihole), dnsmasq) with the
[uklans cache-domains](https://github.com/uklans/cache-domains) list pointed at
this Service's address. Skip it and the workload runs perfectly, reports
healthy, and caches nothing.

The `https` port (`:443`) is the SNI proxy: it forwards TLS rather than
intercepting it, so a domain served over HTTPS passes through uncached and keeps
working.

## It needs egress

The entrypoint refreshes the cache-domains list over git at every boot, and
every cache miss is fetched from the upstream CDN. A NetworkPolicy written from
the shape of the manifest blocks exactly the traffic this workload exists to
make.

```jsonnet
lancache() + kurly.network.kubernetes(allowTo=[{ cidr: '0.0.0.0/0' }])
```

## Sizing

`cacheDiskSize` is a separate number from `cacheSize`, in nginx's own units, and
it is what the cache manager evicts against. Leave headroom below the volume —
the image's own default is `1000g`, which on a smaller volume fills the disk
before eviction ever begins.

## Routing

Clients are pointed here by DNS, never by name, so this is normally published at
layer 4 (a `LoadBalancer` Service on `:80` and `:443`) rather than through an
HTTP router.

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
metadata: { name: kurly, namespace: lancache }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-lancache, namespace: lancache }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/lancache, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: lancache }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-lancache, namespace: lancache }
spec: { sourceRef: { kind: OCIRepository, name: kurly-lancache } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: lancache, namespace: lancache }
spec:
  serviceAccountName: lancache-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/lancache/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-lancache, importPath: github.com/metio/kurly/workloads/lancache }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: lancache, namespace: lancache }
spec:
  serviceAccountName: lancache-deployer
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
        name: lancache
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: lancache }
```

<!-- END generated: jaas-deploy -->
