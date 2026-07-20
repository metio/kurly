<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# emqx

[EMQX](https://www.emqx.io) — a highly-scalable, self-hosted MQTT broker for IoT, with a web dashboard, rules engine and clustering. EMQX speaks MQTT on `:1883`, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local emqx = import 'github.com/metio/kurly/workloads/emqx/server.libsonnet';
kurly.list(emqx())
```

Single node (not a cluster). Expose `:1883` to devices (often a LoadBalancer); the dashboard (`:18083`) needs an extra Service. Data at `/opt/emqx/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves MQTT on `:1883`.

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
metadata: { name: kurly, namespace: emqx }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-emqx, namespace: emqx }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/emqx, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: emqx }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-emqx, namespace: emqx }
spec: { sourceRef: { kind: OCIRepository, name: kurly-emqx } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: emqx, namespace: emqx }
spec:
  serviceAccountName: emqx-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/emqx/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-emqx, importPath: github.com/metio/kurly/workloads/emqx }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: emqx, namespace: emqx }
spec:
  serviceAccountName: emqx-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: emqx
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: emqx }
```

<!-- END generated: jaas-deploy -->
