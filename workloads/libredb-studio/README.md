<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# libredb-studio

[LibreDB Studio](https://libredb.org) — a browser SQL client for PostgreSQL,
MySQL, SQLite, MongoDB, Redis and more: browse schemas, run queries, and keep an
audit trail without installing a desktop client. A plain composable `kurly.http`
workload keeping its own state in SQLite on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local libredb = import 'github.com/metio/kurly/workloads/libredb-studio/server.libsonnet';

kurly.list(libredb())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `libredb-studio` | |
| `image` | `ghcr.io/libredb/libredb-studio:0.9.67` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/app/data` |
| `secretName` | `libredb-studio` | supplies `JWT_SECRET`, `ADMIN_PASSWORD` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:3000` — compose an exposure onto it.

## It is a client, not a database

The servers it connects to are entered by a user at runtime, so nothing has to
exist for this workload to start. It does mean the pod needs egress to wherever
those databases live, which a NetworkPolicy written from the shape of the
manifest will not have guessed:

```jsonnet
libredb() + kurly.network.kubernetes(allowTo=[{ pods: { 'app.kubernetes.io/name': 'postgres' }, ports: [5432] }])
```

## Where its own state goes

`STORAGE_PROVIDER` is set to `sqlite` here, which puts accounts, saved
connections and query history in a file on the volume. The image's own default is
`local` — state in the browser, lost with the tab and shared with nobody — which
is a reasonable default for `docker run` and not for a server several people use.

## The Secret

`JWT_SECRET` signs the tokens users hold and `ADMIN_PASSWORD` is the first
account. Unset, the app generates both on first start, writes them to
`/app/data/auth-bootstrap.json`, and prints the password once to the log. That
survives a restart, because that directory is the volume — but not a move to a
fresh one, and by then the log line has scrolled away.

```shell
kubectl create secret generic libredb-studio \
  --from-literal=JWT_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=ADMIN_EMAIL=admin@example.com \
  --from-literal=ADMIN_PASSWORD="$(head -c 24 /dev/urandom | base64)"
```

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled).

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
metadata: { name: kurly, namespace: libredb-studio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-libredb-studio, namespace: libredb-studio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/libredb-studio, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: libredb-studio }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-libredb-studio, namespace: libredb-studio }
spec: { sourceRef: { kind: OCIRepository, name: kurly-libredb-studio } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: libredb-studio, namespace: libredb-studio }
spec:
  serviceAccountName: libredb-studio-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/libredb-studio/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-libredb-studio, importPath: github.com/metio/kurly/workloads/libredb-studio }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: libredb-studio, namespace: libredb-studio }
spec:
  serviceAccountName: libredb-studio-deployer
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
        name: libredb-studio
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: libredb-studio }
```

<!-- END generated: jaas-deploy -->
