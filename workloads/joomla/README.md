<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# joomla

A Joomla server — a popular self-hosted CMS for building websites and online applications (backed by MySQL). A `kurly.http` workload on the official image, backed by an external database, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local joomla = import 'github.com/metio/kurly/workloads/joomla/server.libsonnet';
kurly.list(joomla())
```

The DB credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/var/www/html` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.

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
metadata: { name: kurly, namespace: joomla }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-joomla, namespace: joomla }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/joomla, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: joomla }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-joomla, namespace: joomla }
spec: { sourceRef: { kind: OCIRepository, name: kurly-joomla } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: joomla, namespace: joomla }
spec:
  serviceAccountName: joomla-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/joomla/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-joomla, importPath: github.com/metio/kurly/workloads/joomla }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: joomla, namespace: joomla }
spec:
  serviceAccountName: joomla-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: joomla
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: joomla }
```

<!-- END generated: jaas-deploy -->
