<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# homepage

[Homepage](https://gethomepage.dev) — a modern, fully static, highly-configurable
application dashboard with service/bookmark widgets and live status. A plain composable
`kurly.http` workload on the official image; its YAML configuration lives on a
PersistentVolume, so it needs no external database.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local homepage = import 'github.com/metio/kurly/workloads/homepage/server.libsonnet';
kurly.list(homepage(allowedHosts='home.example.com'))
```

Set `allowedHosts` (`HOMEPAGE_ALLOWED_HOSTS`) to the host you serve it on — recent
releases reject other Host headers. Config lives at `/app/config` on a ReadWriteOnce
volume, so this is **one replica, recreated**. Serves on `:3000`.

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
metadata: { name: kurly, namespace: homepage }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-homepage, namespace: homepage }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/homepage, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: homepage }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-homepage, namespace: homepage }
spec: { sourceRef: { kind: OCIRepository, name: kurly-homepage } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: homepage, namespace: homepage }
spec:
  serviceAccountName: homepage-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/homepage/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-homepage, importPath: github.com/metio/kurly/workloads/homepage }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: homepage, namespace: homepage }
spec:
  serviceAccountName: homepage-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: homepage
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: homepage }
```

<!-- END generated: jaas-deploy -->
