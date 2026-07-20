<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# drawio

[draw.io / diagrams.net](https://github.com/jgraph/drawio) — the self-hosted web editor
for flowcharts, UML and network diagrams. A plain composable `kurly.http` workload on the
official image; the editor runs in the browser and stores diagrams wherever the user
chooses, so the server is **stateless**.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local drawio = import 'github.com/metio/kurly/workloads/drawio/server.libsonnet';
kurly.list(drawio())
```

Serves the editor on `:8080`.

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
metadata: { name: kurly, namespace: drawio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-drawio, namespace: drawio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/drawio, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: drawio }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-drawio, namespace: drawio }
spec: { sourceRef: { kind: OCIRepository, name: kurly-drawio } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: drawio, namespace: drawio }
spec:
  serviceAccountName: drawio-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/drawio/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-drawio, importPath: github.com/metio/kurly/workloads/drawio }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: drawio, namespace: drawio }
spec:
  serviceAccountName: drawio-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: drawio
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: drawio }
```

<!-- END generated: jaas-deploy -->
