<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# khoj

[Khoj](https://github.com/khoj-ai/khoj) — searches your own documents and the
web and answers questions from them. A composable `kurly.http` workload backed
by an external PostgreSQL, with its configuration, index and model cache on
PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local khoj = import 'github.com/metio/kurly/workloads/khoj/server.libsonnet';

kurly.list(khoj())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `khoj` | |
| `image` | `ghcr.io/khoj-ai/khoj:2.0.0-beta.28` | |
| `storageSize` / `cacheSize` / `storageClass` | `10Gi` / `10Gi` / cluster default | `/root/.khoj` and `/root/.cache` |
| `dbHost` / `dbPort` / `database` / `dbUser` | `khoj-db-rw` … | pairs with a `cnpg-cluster` named `khoj-db` |
| `domain` | none | the public host the instance is reached at |
| `anonymousMode` | `false` | serve without accounts |
| `secretName` | `khoj` | four credentials, see below |

## The database needs pgvector

Khoj stores and queries its embeddings as vectors, so the PostgreSQL it connects
to must have the `pgvector` extension available — upstream ships its own
`pgvector`-carrying image for exactly this. A plain PostgreSQL lets the server
start and then fails every search.

## Supply the Secret

```shell
kubectl create secret generic khoj \
  --from-literal=POSTGRES_PASSWORD=… \
  --from-literal=KHOJ_DJANGO_SECRET_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=KHOJ_ADMIN_EMAIL=you@example.com \
  --from-literal=KHOJ_ADMIN_PASSWORD=…
```

`KHOJ_DJANGO_SECRET_KEY` signs sessions and has a published default in the
project's own compose file — supplying it is the difference between having
accounts and not. The admin pair creates the first Django superuser on start;
sign in at `/server/admin`.

## Set `domain` before exposing it

Django validates the `Host` header, and `ALLOWED_HOSTS` plus the CSRF origins are
built from `KHOJ_DOMAIN`. Without it a login through an exposure is rejected. For
the same reason the probes here are **connection** probes: an HTTP probe from the
kubelet arrives with the pod IP as its `Host`, which Khoj answers with a 400 —
and a liveness probe that fails forever kills the pod forever.

## Two volumes, and a slow first start

`/root/.khoj` holds the configuration and the indexed content. `/root/.cache`
holds the embedding models Khoj downloads on first start; it is not state you
must keep, but on an `emptyDir` every restart re-downloads gigabytes before the
app answers anything. That download, plus the Django migrations, is why the
startup probe allows ten minutes.

Both volumes are ReadWriteOnce, so this is **one replica, recreated** (never
rolled).

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
metadata: { name: kurly, namespace: khoj }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-khoj, namespace: khoj }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/khoj, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: khoj }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-khoj, namespace: khoj }
spec: { sourceRef: { kind: OCIRepository, name: kurly-khoj } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: khoj, namespace: khoj }
spec:
  serviceAccountName: khoj-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/khoj/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-khoj, importPath: github.com/metio/kurly/workloads/khoj }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: khoj, namespace: khoj }
spec:
  serviceAccountName: khoj-deployer
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
        name: khoj
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: khoj }
```

<!-- END generated: jaas-deploy -->
