<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# whoogle

[Whoogle Search](https://github.com/benbusby/whoogle-search) — a self-hosted, privacy-respecting metasearch proxy for Google results: no ads, no tracking, no JavaScript required. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local whoogle = import 'github.com/metio/kurly/workloads/whoogle/server.libsonnet';
kurly.list(whoogle())
```

Configure through `WHOOGLE_CONFIG_*` env vars. Serves on `:5000`.

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
metadata: { name: kurly, namespace: whoogle }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-whoogle, namespace: whoogle }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/whoogle, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: whoogle }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-whoogle, namespace: whoogle }
spec: { sourceRef: { kind: OCIRepository, name: kurly-whoogle } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: whoogle, namespace: whoogle }
spec:
  serviceAccountName: whoogle-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/whoogle/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-whoogle, importPath: github.com/metio/kurly/workloads/whoogle }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: whoogle, namespace: whoogle }
spec:
  serviceAccountName: whoogle-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: whoogle
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: whoogle }
```

<!-- END generated: jaas-deploy -->
