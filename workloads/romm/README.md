<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# romm

[RomM](https://romm.app/) — scans a ROM library, enriches it with metadata from
the games databases, and browses or plays it in the browser. A composable
`kurly.http` workload backed by an external MariaDB/MySQL, with the library,
scraped resources and uploaded assets on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local romm = import 'github.com/metio/kurly/workloads/romm/server.libsonnet';

kurly.list(romm())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `romm` | |
| `image` | `ghcr.io/rommapp/romm:5.1.0` | |
| `storageSize` / `storageClass` | `100Gi` / cluster default | `/romm` |
| `dbHost` / `dbPort` / `database` / `dbUser` | `romm-db` … | pairs with a `mysql-cluster` named `romm-db` |
| `secretName` | `romm` | see below |

## Supply the Secret

```shell
kubectl create secret generic romm \
  --from-literal=DB_PASSWD=… \
  --from-literal=ROMM_AUTH_SECRET_KEY="$(openssl rand -hex 32)"
```

`ROMM_AUTH_SECRET_KEY` signs the sessions users hold: change it and everybody is
logged out, lose it and nobody can log in. Metadata scraping needs credentials
of its own — `IGDB_CLIENT_ID` / `IGDB_CLIENT_SECRET`, `MOBYGAMES_API_KEY`,
`STEAMGRIDDB_API_KEY` — and they belong in the same Secret. Without any of them
the library still imports; it simply arrives without cover art or titles.

## Less hardened, deliberately

`s6` supervises nginx and the Python backend and drops privileges to their
accounts, which it can only do starting from root, and the entrypoint chowns the
data volume on the way. The root filesystem is writable because nginx, s6 and the
Valkey the image bundles all keep their pid files, sockets and data inside the
image's own tree.

## Persistence and scale

The library, the scraped resources and the uploaded assets all live under `/romm`
on a ReadWriteOnce volume, so this is **one replica, recreated** (never rolled).
Everything the application indexes is in the database — point `dbHost` at one
that is backed up, and size the volume for the ROMs themselves, which is the part
that grows.

A first scan of a large library takes a long time and runs entirely inside the
pod; the startup probe allows five minutes before the liveness probe starts
counting.

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
metadata: { name: kurly, namespace: romm }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-romm, namespace: romm }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/romm, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: romm }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-romm, namespace: romm }
spec: { sourceRef: { kind: OCIRepository, name: kurly-romm } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: romm, namespace: romm }
spec:
  serviceAccountName: romm-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/romm/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-romm, importPath: github.com/metio/kurly/workloads/romm }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: romm, namespace: romm }
spec:
  serviceAccountName: romm-deployer
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
        name: romm
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: romm }
```

<!-- END generated: jaas-deploy -->
