<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# manticore

[Manticore Search](https://github.com/manticoresoftware/manticoresearch) — a
full-text search and analytics database. SQL over a MySQL-compatible port, JSON
over HTTP, full-text and vector search in one engine. A plain composable
`kurly.http` workload whose indexes live on a PersistentVolume; it needs nothing
external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local manticore = import 'github.com/metio/kurly/workloads/manticore/server.libsonnet';

kurly.list(manticore())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `manticore` | |
| `image` | `manticoresearch/manticore:9.3.2` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | indexes (`/var/lib/manticore`) |
| `env` / `resources` / `labels` / `annotations` | | give it memory for large indexes |

## Ports, and a warning about exposing it

| port | protocol | for |
|---|---|---|
| 9308 | HTTP | the JSON API — the one an exposure attaches to |
| 9306 | TCP | the MySQL protocol, what `mysql -P9306` and most clients speak |
| 9312 | TCP | the binary protocol, for replication between nodes |

**Manticore has no authentication of its own.** It answers whoever reaches it, so
an exposure on :9308 publishes an unauthenticated database that anyone can read
and write. Keep it inside the cluster and reach it from your own application, or
put something in front that authenticates. The MySQL and replication ports are not
HTTP and cannot be carried by an Ingress or HTTPRoute in any case.

## Running unprivileged

The entrypoint chowns its directories and drops to the `manticore` account with
`gosu` — but only when it starts as root, testing `id -u` first and otherwise
running `searchd` directly. Naming that account (uid 999, the one the image
builds) takes the second path, so the **restricted** posture holds and `fsGroup`
makes the volume writable instead. It is the same shape
[opengist](../opengist/) and [cloudbeaver](../cloudbeaver/) turned out to have,
and the opposite of [archivebox](../archivebox/), which has no such path.

## Three writable paths, one of them surprising

`searchd` writes outside its data directory, and the third of these cost a boot to
find:

- `/var/log/manticore` — its log
- `/var/run/manticore` — its pid file
- **`/var/run/mysqld`** — the shipped configuration listens on a UNIX socket at
  `/var/run/mysqld/mysqld.sock`, a *mysqld* path inside a search engine, and
  `searchd` unlinks it before binding. On a read-only filesystem that is fatal,
  and the only clue is `unlink() on UNIX socket file failed: Read-only file
  system` — which names neither the path nor the setting that chose it.

All three are ephemeral scratch, not volumes: nothing there is worth keeping.

## Persistence

One index directory on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two `searchd` processes off the same files.

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
metadata: { name: kurly, namespace: manticore }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-manticore, namespace: manticore }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/manticore, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: manticore }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-manticore, namespace: manticore }
spec: { sourceRef: { kind: OCIRepository, name: kurly-manticore } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: manticore, namespace: manticore }
spec:
  serviceAccountName: manticore-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/manticore/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-manticore, importPath: github.com/metio/kurly/workloads/manticore }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: manticore, namespace: manticore }
spec:
  serviceAccountName: manticore-deployer
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
        name: manticore
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: manticore }
```

<!-- END generated: jaas-deploy -->
