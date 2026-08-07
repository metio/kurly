<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# receipt-wrangler

[Receipt Wrangler](https://github.com/Receipt-Wrangler/receipt-wrangler) — scan
or upload a receipt, have it categorised, and split what it cost between the
people who shared it. A composable `kurly.http` workload backed by an external
PostgreSQL and an external Redis, with uploaded receipt images on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local receiptWrangler = import 'github.com/metio/kurly/workloads/receipt-wrangler/server.libsonnet';

kurly.list(receiptWrangler())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `receipt-wrangler` | |
| `image` | `docker.io/noah231515/receipt-wrangler:v7.1.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/app/receipt-wrangler-api/data` |
| `dbHost` / `dbPort` / `database` / `dbUser` | `receipt-wrangler-db-rw` … | pairs with a `cnpg-cluster` named `receipt-wrangler-db` |
| `redisHost` / `redisPort` | `receipt-wrangler-cache-headless` / `6379` | pairs with a `valkey` named `receipt-wrangler-cache` |
| `secretName` | `receipt-wrangler` | three credentials, see below |

## Redis is not optional

The API runs its task queue (asynq) in-process: the worker and the scheduler
start inside the same binary that serves the API, and a failed Redis connection
is fatal. A deployment with a database and no Redis never starts — point
`redisHost` at one before anything else.

## Supply the Secret

Two of the three keys are refused as empty at startup, so the pod does not come
up without them.

| key | what it protects |
|---|---|
| `DB_PASSWORD` | the PostgreSQL login |
| `SECRET_KEY` | the tokens that sign users in |
| `ENCRYPTION_KEY` | the stored mail-account credentials it polls receipts from |

```shell
kubectl create secret generic receipt-wrangler \
  --from-literal=DB_PASSWORD=… \
  --from-literal=SECRET_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=ENCRYPTION_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

A Redis that requires authentication adds `REDIS_PASSWORD` (and `REDIS_USER`)
to the same Secret; leave both out for one that does not, because an `AUTH` sent
to a Redis without a password set is an error rather than a no-op.

## Less hardened, deliberately

The entrypoint runs the Go API and nginx side by side as root — nginx binds
`:80` and drops to its own account, which it can only do starting from root — so
root, privilege escalation and capabilities are relaxed. The root filesystem is
writable because nginx keeps its pid, logs and temporary bodies inside the
image's own tree and the API writes its log files beside its binary.

Service links are disabled: a cache Service called `redis` in the same namespace
injects `REDIS_PORT` as a `tcp://` URL, and this API parses that variable as an
integer.

## Persistence

Uploaded receipt images live on a ReadWriteOnce volume, so this is **one
replica, recreated** (never rolled). Everything else is in PostgreSQL — point
`dbHost` at one that is backed up.

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
metadata: { name: kurly, namespace: receipt-wrangler }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-receipt-wrangler, namespace: receipt-wrangler }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/receipt-wrangler, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: receipt-wrangler }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-receipt-wrangler, namespace: receipt-wrangler }
spec: { sourceRef: { kind: OCIRepository, name: kurly-receipt-wrangler } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: receipt-wrangler, namespace: receipt-wrangler }
spec:
  serviceAccountName: receipt-wrangler-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/receipt-wrangler/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-receipt-wrangler, importPath: github.com/metio/kurly/workloads/receipt-wrangler }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: receipt-wrangler, namespace: receipt-wrangler }
spec:
  serviceAccountName: receipt-wrangler-deployer
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
        name: receipt-wrangler
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: receipt-wrangler }
```

<!-- END generated: jaas-deploy -->
