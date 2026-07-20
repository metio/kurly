<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# invoiceninja

[Invoice Ninja](https://github.com/invoiceninja/invoiceninja) — self-hosted
invoicing, quotes, and payments. A plain composable `kurly.http` workload on the
official image, backed by an external MySQL/MariaDB, with its uploads and generated
PDFs on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local invoiceninja = import 'github.com/metio/kurly/workloads/invoiceninja/server.libsonnet';

kurly.list(invoiceninja(appUrl='https://invoicing.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `invoiceninja` | |
| `image` | `docker.io/invoiceninja/invoiceninja:5.13.26` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | uploads and PDFs (`/var/www/html/storage`) |
| `dbHost` / `dbName` / `dbUser` | `invoiceninja-db` / `invoiceninja` / `invoiceninja` | the MySQL/MariaDB database |
| `appUrl` | inferred | the public URL |
| `secretName` | `invoiceninja-secrets` | Secret with `DB_PASSWORD` and `APP_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it.

## Database and secrets

Invoice Ninja needs a **MySQL/MariaDB** database. kurly ships no MySQL recipe —
bring your own (an operator-managed instance, or one you run) and point `dbHost` at
it. It reads `DB_HOST`, `DB_DATABASE`, `DB_USERNAME` from env and `DB_PASSWORD` and
`APP_KEY` from a provided Secret via `envFrom`. kurly authors **no Secret** — fill
`invoiceninja-secrets` with [`kurly.externalSecret`](../../main.libsonnet).

## Security and persistence

The nginx + PHP-FPM image starts as **root** and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. Uploads and PDFs live on a ReadWriteOnce
volume, so this is **one replica, recreated**. A separate queue worker (for emails
and background jobs) can be added by composing a second deployment running
`php artisan queue:work`.

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
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: invoiceninja }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-invoiceninja, namespace: invoiceninja }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/invoiceninja, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: invoiceninja }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-invoiceninja, namespace: invoiceninja }
spec: { sourceRef: { kind: OCIRepository, name: kurly-invoiceninja } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: invoiceninja, namespace: invoiceninja }
spec:
  serviceAccountName: invoiceninja-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/invoiceninja/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-invoiceninja, importPath: github.com/metio/kurly/workloads/invoiceninja }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: invoiceninja, namespace: invoiceninja }
spec:
  serviceAccountName: invoiceninja-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: invoiceninja
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: invoiceninja }
```

<!-- END generated: jaas-deploy -->
