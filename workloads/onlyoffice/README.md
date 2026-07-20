<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# onlyoffice

[ONLYOFFICE Document Server](https://www.onlyoffice.com) — a self-hosted online office suite for collaborative editing of documents, spreadsheets and presentations, embedded by Nextcloud, Seafile and others. A `kurly.http` workload on the official image; data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local onlyoffice = import 'github.com/metio/kurly/workloads/onlyoffice/server.libsonnet';
kurly.list(onlyoffice())
```

The app that embeds it points its ONLYOFFICE connector at this URL. `JWT_SECRET` comes from a Secret via `envFrom` — kurly authors **no Secret**. The image bundles its own PostgreSQL and RabbitMQ. Data at `/var/www/onlyoffice/Data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.

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
metadata: { name: kurly, namespace: onlyoffice }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-onlyoffice, namespace: onlyoffice }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/onlyoffice, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: onlyoffice }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-onlyoffice, namespace: onlyoffice }
spec: { sourceRef: { kind: OCIRepository, name: kurly-onlyoffice } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: onlyoffice, namespace: onlyoffice }
spec:
  serviceAccountName: onlyoffice-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/onlyoffice/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-onlyoffice, importPath: github.com/metio/kurly/workloads/onlyoffice }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: onlyoffice, namespace: onlyoffice }
spec:
  serviceAccountName: onlyoffice-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: onlyoffice
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: onlyoffice }
```

<!-- END generated: jaas-deploy -->
