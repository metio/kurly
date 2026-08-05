<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# warracker

[Warracker](https://github.com/sassanix/Warracker) — keeps track of product
warranties: what you bought, when the cover expires, and the receipts and manuals
that go with it, with reminders before each one lapses. A composable
`kurly.http` workload backed by an external PostgreSQL, with uploaded documents
on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local warracker = import 'github.com/metio/kurly/workloads/warracker/server.libsonnet';

kurly.list(warracker())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `warracker` | |
| `image` | `ghcr.io/sassanix/warracker/main:1.0.2` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/data/uploads` |
| `dbHost` / `dbPort` / `database` / `dbUser` | `warracker-db-rw` … | pairs with a `cnpg-cluster` named `warracker-db` |
| `secretName` | `warracker` | three credentials, see below |

## Supply the Secret — every default is published

The project's own compose file ships defaults for all three:

| key | what it protects |
|---|---|
| `DB_PASSWORD` | the application's database login |
| `DB_ADMIN_PASSWORD` | the migration/admin login |
| `SECRET_KEY` | Flask sessions and JWTs |

Upstream's placeholders are literally `warranty_password`,
`change_this_password_in_production` and
`your_very_secret_flask_key_change_me`. Running with them is not a weakened
posture — it means anybody who has read the repository can mint a session.

```shell
kubectl create secret generic warracker \
  --from-literal=DB_PASSWORD=… \
  --from-literal=DB_ADMIN_PASSWORD=… \
  --from-literal=SECRET_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## Less hardened, deliberately

`supervisord` runs nginx and gunicorn together and drops privileges to their
accounts, which it can only do starting from root; nginx also binds `:80`. The
root filesystem is writable because both keep their pid, logs and temporary
bodies inside the image's own tree.

## Persistence

Uploaded receipts and manuals live on a ReadWriteOnce volume, so this is **one
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
metadata: { name: kurly, namespace: warracker }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-warracker, namespace: warracker }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/warracker, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: warracker }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-warracker, namespace: warracker }
spec: { sourceRef: { kind: OCIRepository, name: kurly-warracker } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: warracker, namespace: warracker }
spec:
  serviceAccountName: warracker-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/warracker/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-warracker, importPath: github.com/metio/kurly/workloads/warracker }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: warracker, namespace: warracker }
spec:
  serviceAccountName: warracker-deployer
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
        name: warracker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: warracker }
```

<!-- END generated: jaas-deploy -->
