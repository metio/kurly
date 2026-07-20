<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# phpmyadmin

[phpMyAdmin](https://www.phpmyadmin.net) — the classic web UI for administering MySQL and MariaDB. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local phpmyadmin = import 'github.com/metio/kurly/workloads/phpmyadmin/server.libsonnet';
kurly.list(phpmyadmin(dbHost='mysql'))
```

Point it at the MySQL/MariaDB host through `dbHost` (`PMA_HOST`). Serves on `:80`.

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
metadata: { name: kurly, namespace: phpmyadmin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-phpmyadmin, namespace: phpmyadmin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/phpmyadmin, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: phpmyadmin }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-phpmyadmin, namespace: phpmyadmin }
spec: { sourceRef: { kind: OCIRepository, name: kurly-phpmyadmin } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: phpmyadmin, namespace: phpmyadmin }
spec:
  serviceAccountName: phpmyadmin-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/phpmyadmin/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-phpmyadmin, importPath: github.com/metio/kurly/workloads/phpmyadmin }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: phpmyadmin, namespace: phpmyadmin }
spec:
  serviceAccountName: phpmyadmin-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: phpmyadmin
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: phpmyadmin }
```

<!-- END generated: jaas-deploy -->
