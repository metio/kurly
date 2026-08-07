<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# calagopus

[Calagopus](https://github.com/calagopus/panel) — a game server management panel:
it creates game servers on wings nodes, hands their owners a console, files and
backups, and keeps the accounts and permissions around them. A composable
`kurly.http` workload on the official single-binary image, backed by an external
PostgreSQL and an external Redis/valkey, with the panel's data directory on a
PersistentVolume.

The panel is only half a deployment: the servers themselves run on **wings**
daemons, which are not carried here — they want a host with Docker, which is a
node, not a pod.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local calagopus = import 'github.com/metio/kurly/workloads/calagopus/server.libsonnet';

kurly.list(calagopus())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `calagopus` | |
| `image` | `ghcr.io/calagopus/panel:latest` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/var/lib/calagopus` |
| `primary` | `true` | this instance runs the background tasks |
| `migrate` | `true` | migrate the schema on start |
| `secretName` | `calagopus` | three keys, see below |

## Supply the Secret

```shell
kubectl create secret generic calagopus \
  --from-literal=DATABASE_URL='postgresql://calagopus:…@calagopus-db-rw:5432/calagopus' \
  --from-literal=REDIS_URL='redis://:…@calagopus-cache:6379' \
  --from-literal=APP_ENCRYPTION_KEY="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

`APP_ENCRYPTION_KEY` protects the node and server credentials the panel stores in
its database, and upstream's own compose file ships it as the literal `CHANGEME`
— an instance started with that has those credentials readable by anybody who has
read the repository. Changing it later does not re-encrypt what is already
stored.

## Dependencies

PostgreSQL and a Redis-compatible cache, both external: pair it with a
`cnpg-cluster` named `calagopus-db` and a `valkey` named `calagopus-cache`. The
panel also talks to the wings daemons it manages over the network, so a
NetworkPolicy that allows only the database and the cache leaves every server
unreachable from the panel.

## Persistence

The data directory is on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). A second instance is a deliberate act: `APP_PRIMARY`
decides which one runs the cleanups and schedules, and exactly one may have it.

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
metadata: { name: kurly, namespace: calagopus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-calagopus, namespace: calagopus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/calagopus, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: calagopus }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-calagopus, namespace: calagopus }
spec: { sourceRef: { kind: OCIRepository, name: kurly-calagopus } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: calagopus, namespace: calagopus }
spec:
  serviceAccountName: calagopus-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/calagopus/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-calagopus, importPath: github.com/metio/kurly/workloads/calagopus }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: calagopus, namespace: calagopus }
spec:
  serviceAccountName: calagopus-deployer
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
        name: calagopus
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: calagopus }
```

<!-- END generated: jaas-deploy -->
