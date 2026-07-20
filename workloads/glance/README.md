<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# glance

[Glance](https://github.com/glanceapp/glance) — a self-hosted dashboard that puts your feeds, RSS, weather, markets, monitoring and homelab widgets on one fast page. A `kurly.http` workload on the official image; its layout is a `glance.yml` mounted as a ConfigMap.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local glance = import 'github.com/metio/kurly/workloads/glance/server.libsonnet';
kurly.list(glance(config={ pages: [{ name: 'Home', columns: [{ size: 'full', widgets: [{ type: 'clock' }] }] }] }))
```

`config` is Glance's own `glance.yml`, mounted verbatim — kurly does not model it. Stateless — the default shows a minimal page. Serves on `:8080`.

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
metadata: { name: kurly, namespace: glance }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-glance, namespace: glance }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/glance, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: glance }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-glance, namespace: glance }
spec: { sourceRef: { kind: OCIRepository, name: kurly-glance } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: glance, namespace: glance }
spec:
  serviceAccountName: glance-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/glance/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-glance, importPath: github.com/metio/kurly/workloads/glance }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: glance, namespace: glance }
spec:
  serviceAccountName: glance-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: glance
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: glance }
```

<!-- END generated: jaas-deploy -->
