<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# netbox

[NetBox](https://netboxlabs.com/oss/netbox/) — the IPAM/DCIM source of truth: IP
address management, data-center infrastructure modelling, cabling, and a full
REST/GraphQL API. Two composable stages running the
[community image](https://github.com/netbox-community/netbox-docker): `server` (the
web front end, `kurly.http`) and `worker` (the RQ background worker, `kurly.worker`).

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local netbox = import 'github.com/metio/kurly/workloads/netbox/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/netbox/worker.libsonnet';

kurly.listOf([
  netbox(allowedHosts='netbox.example.com'),
  worker(),
])
```

### `server`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `netbox` | |
| `image` | `docker.io/netboxcommunity/netbox:v4.6.5` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the uploaded-media volume |
| `dbHost` / `dbName` / `dbUser` | `netbox-db-rw` / `netbox` / `netbox` | the PostgreSQL database — see below |
| `redisHost` | `netbox-cache` | the Redis instance (queue on DB 0, cache on DB 1) |
| `secretName` | `netbox-secrets` | the Secret read at `/run/secrets` — see below |
| `allowedHosts` | `*` | space-separated Django `ALLOWED_HOSTS` |
| `superuserName` / `superuserEmail` / `skipSuperuser` | `admin` / `admin@example.com` / `false` | the first-boot admin |
| `env` | `{}` | extra environment (`SKIP_STARTUP_SCRIPTS`, `EMAIL_*`, `CORS_*`, …) |
| `resources` / `labels` / `annotations` | | |

### `worker`

| Parameter | Default | Notes |
|---|---|---|
| `name` | `netbox-worker` | |
| `image` | `docker.io/netboxcommunity/netbox:v4.6.5` | same image as the server |
| `dbHost` / `dbName` / `dbUser` / `redisHost` / `secretName` | as the server | |
| `replicas` | `1` | scale out freely — workers coordinate through Redis |
| `env` / `resources` / `labels` / `annotations` | | |

The server serves the UI and API on `:8080` — compose an exposure onto it:

```jsonnet
kurly.listOf([
  netbox(allowedHosts='netbox.example.com')
  + kurly.expose.ownGateway('netbox.example.com', 'istio', tls='netbox-tls'),
  kurly.certificate('netbox-tls', ['netbox.example.com'], 'letsencrypt-prod'),
  worker(),
])
```

## Database and cache (the cnpg + valkey pairing)

NetBox needs **PostgreSQL** and **Redis**. The defaults pair with the
[cnpg-cluster](../cnpg-cluster/) and [valkey](../valkey/) workloads: a CNPG cluster
named `netbox-db` and a Valkey named `netbox-cache`. NetBox uses two logical Redis
databases on that one instance — `0` for the task queue, `1` for the cache.

```jsonnet
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/instance.libsonnet';

kurly.listOf([
  cnpg(name='netbox-db', database='netbox'),
  valkey(name='netbox-cache'),
  netbox(allowedHosts='netbox.example.com'),
  worker(),
])
```

## Secrets

kurly authors **no Secret**. The image reads its secrets from files under
`/run/secrets`, so both stages mount one consumer-provided Secret there. It must
carry:

| Key | Used by | Notes |
|---|---|---|
| `secret_key` | server, worker | Django `SECRET_KEY`, ≥50 chars — **keep it stable**, sessions and stored data depend on it |
| `db_password` | server, worker | the PostgreSQL password (matching the CNPG `-app` Secret) |
| `superuser_password` | server | only needed on first bring-up; drop it (or set `skipSuperuser=true`) afterwards |

Fill it with [`kurly.externalSecret`](../../main.libsonnet) from your secret store,
or copy the CNPG-generated `db_password` in by hand.

## Persistence and scale

One PersistentVolume holds uploaded media, so the **server** is one replica,
recreated (never rolled) to keep two pods off the ReadWriteOnce volume — the same
single-writer discipline as [tik](../tik/). The **worker** holds no state and
scales horizontally: bump `replicas`, and the workers drain the shared Redis queue
side by side. A NetBox deployment needs at least one worker running — webhooks,
report and script runs, and housekeeping are all enqueued jobs.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: netbox }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-netbox, namespace: netbox }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/netbox, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: netbox }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-netbox, namespace: netbox }
spec: { sourceRef: { kind: OCIRepository, name: kurly-netbox } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: netbox-server, namespace: netbox }
spec:
  serviceAccountName: netbox-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/netbox/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-netbox, importPath: github.com/metio/kurly/workloads/netbox }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: netbox-worker, namespace: netbox }
spec:
  serviceAccountName: netbox-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local worker = import 'github.com/metio/kurly/workloads/netbox/worker.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(worker())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-netbox, importPath: github.com/metio/kurly/workloads/netbox }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: netbox, namespace: netbox }
spec:
  serviceAccountName: netbox-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: netbox-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: netbox-server }
    - name: worker
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: netbox-worker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: netbox-worker }
```

<!-- END generated: jaas-deploy -->
