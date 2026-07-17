<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# memcached

An in-memory cache sharded by the **client**, as a StatefulSet whose storage is
nothing and whose identity is everything.

memcached has no replication and no persistence. Unlike the
[valkey cache](../valkey/), it cannot hand its dataset to a new version — every
upgrade starts cold. What it offers instead is **bounded loss**: clients pick a
server by consistent-hashing each key over the server list, so as long as the
names in that list hold still, restarting one pod costs a client the 1/N of its
keyspace that lived there, and nothing else.

That is why this is a StatefulSet. It is here for stable names
(`memcached-0`, `memcached-1`, …) and their DNS records, **not** for storage —
there is no volume anywhere in this workload. Authored as a Deployment the
manifests would look much the same and behave completely differently: every pod
would get a fresh random name on every roll, every name in the client's hash ring
would change at once, and the whole cache would be invalidated rather than 1/N of
it.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local memcached = import 'github.com/metio/kurly/workloads/memcached/cache.libsonnet';

kurly.list(memcached(replicas=3, memoryMB=256))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `memcached` | names every object, and the DNS the client list is built from |
| `image` | `docker.io/library/memcached:1.6.45` | |
| `replicas` | `3` | the shard count — part of the client's configuration (see below) |
| `memoryMB` | `64` | `-m`, the item cache size; also derives the container memory limit |
| `maxConnections` | `1024` | `-c` |

## Connecting

Clients address the pods **directly**, by their stable DNS names — not through a
load balancer, because a shard is not interchangeable with any other shard:

```text
memcached-0.memcached-headless:11211
memcached-1.memcached-headless:11211
memcached-2.memcached-headless:11211
```

Those names follow `name`, so `memcached(name='sessions')` publishes
`sessions-0.sessions-headless` and a namespace can hold more than one cache.

Give that list to a client that consistent-hashes over it (pymemcache's
`HashClient`, `spymemcached`, `Enyim`, …).

## Two things to know before adopting this

**Scaling reshuffles the ring.** Changing `replicas` changes the server list, and
a client that hashes over it will map many existing keys to a different pod —
which does not hold them. The effect is a large, sudden cache miss rate, not an
error, so it is easy to miss in a dashboard. Treat `replicas` as part of the
client's configuration and change it deliberately.

**The container memory limit is derived, not passed.** `-m` caps the *item cache
only*: slab metadata, per-connection buffers, and the binary itself live outside
it, so a limit equal to `-m` is an OOMKill waiting for a busy day. The limit
comes from the same `memoryMB` that produces `-m` (plus 25% and 32Mi), so the two
cannot drift — the usual failure being an `-m` raised without the limit following
it.

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-memcached, namespace: cache }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/memcached
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-memcached, namespace: cache }
spec: { sourceRef: { kind: OCIRepository, name: kurly-memcached } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: memcached, namespace: cache }
spec:
  serviceAccountName: cache-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local memcached = import 'github.com/metio/kurly/workloads/memcached/cache.libsonnet';
      function(replicas='3', memoryMB='256')
        kurly.list(memcached(replicas=std.parseInt(replicas), memoryMB=std.parseInt(memoryMB)))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,           importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-memcached, importPath: github.com/metio/kurly/workloads/memcached }
  tlas:
    - name: replicas
      value: "3"
    - name: memoryMB
      value: "256"
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: memcached, namespace: cache }
spec:
  serviceAccountName: cache-deployer
  stages:
    - name: cache
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: memcached
      readyChecks:
        checks:
          - apiVersion: apps/v1
            kind: StatefulSet
            name: memcached
```
