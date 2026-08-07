<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# habitat

[Habitat](https://github.com/carlnewton/habitat) — a message board for one place:
residents post about their neighbourhood, and a post can be pinned to a location
so people find the conversations happening near them. A composable `kurly.http`
workload: a Symfony application served by FrankenPHP, backed by an external
PostgreSQL, with uploaded images on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local habitat = import 'github.com/metio/kurly/workloads/habitat/server.libsonnet';

kurly.list(habitat(url='https://habitat.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `habitat` | |
| `image` | `docker.io/carlnewton/habitat:1.6.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/uploads` |
| `port` | `8080` | what Caddy listens on |
| `url` | unset | the address the instance is reached at |
| `secretName` | `habitat` | five credentials, see below |

## Supply the Secret

`DATABASE_URL` carries the PostgreSQL password, so the whole connection string
lives in the Secret rather than being split across environment.

| key | what it is |
|---|---|
| `DATABASE_URL` | `postgresql://user:pass@host:5432/habitat?serverVersion=16&charset=utf8` |
| `APP_SECRET` | signs Symfony's cookies |
| `ENCRYPTION_KEY` | encrypts the instance settings stored in the database |
| `MERCURE_PUBLISHER_JWT_KEY` / `MERCURE_SUBSCRIBER_JWT_KEY` | the Mercure hub Caddy serves |

Upstream's compose file ships published placeholders for all of them
(`!ChangeThisAppSecret!` and friends), so supplying real values is the
difference between having accounts and not.

```shell
kubectl create secret generic habitat \
  --from-literal=DATABASE_URL='postgresql://habitat:…@habitat-db-rw:5432/habitat?serverVersion=16&charset=utf8' \
  --from-literal=APP_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=ENCRYPTION_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=MERCURE_PUBLISHER_JWT_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=MERCURE_SUBSCRIBER_JWT_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

**`ENCRYPTION_KEY` is not rotatable in place.** The instance settings in the
database are encrypted with it; a new value makes them unreadable.

## Plain HTTP in the pod

`SERVER_NAME` is set to `:8080`, so the Caddy inside FrankenPHP serves plain
HTTP and never tries to obtain a certificate. TLS belongs to the exposure
composed onto the Service.

## First start runs the migrations

The entrypoint waits for the database and runs the Doctrine migrations before it
serves anything, so a first start on an empty database takes minutes. That is
why the stage carries a startup probe with a long budget — a `StageSet`
deploying it needs a `timeout` past the same budget.

## Persistence

Images attached to posts live at `/uploads` on a ReadWriteOnce volume, so this
is **one replica, recreated** (never rolled). Everything else is in PostgreSQL —
point `DATABASE_URL` at one that is backed up.

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
metadata: { name: kurly, namespace: habitat }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-habitat, namespace: habitat }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/habitat, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: habitat }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-habitat, namespace: habitat }
spec: { sourceRef: { kind: OCIRepository, name: kurly-habitat } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: habitat, namespace: habitat }
spec:
  serviceAccountName: habitat-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/habitat/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-habitat, importPath: github.com/metio/kurly/workloads/habitat }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: habitat, namespace: habitat }
spec:
  serviceAccountName: habitat-deployer
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
        name: habitat
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: habitat }
```

<!-- END generated: jaas-deploy -->
