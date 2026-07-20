<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# openhab

[openHAB](https://www.openhab.org) — a vendor-neutral, self-hosted home-automation platform integrating a huge range of devices behind one engine, UI and rule system. A `kurly.http` workload on the official image; its three persistent directories each get their own PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local openhab = import 'github.com/metio/kurly/workloads/openhab/server.libsonnet';
kurly.list(openhab())
```

openHAB keeps config at `/openhab/conf`, runtime userdata at `/openhab/userdata`, and add-ons at `/openhab/addons`, so the workload composes `kurly.store` **three times** (sized by `confSize`/`userdataSize`/`addonsSize`), one PVC each. USB/serial radios are hardware and not modelled — use a network coordinator. All volumes are ReadWriteOnce, so **one replica, recreated**. Serves on `:8080`.

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
metadata: { name: kurly, namespace: openhab }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-openhab, namespace: openhab }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/openhab, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: openhab }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-openhab, namespace: openhab }
spec: { sourceRef: { kind: OCIRepository, name: kurly-openhab } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: openhab, namespace: openhab }
spec:
  serviceAccountName: openhab-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/openhab/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-openhab, importPath: github.com/metio/kurly/workloads/openhab }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: openhab, namespace: openhab }
spec:
  serviceAccountName: openhab-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: openhab
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: openhab }
```

<!-- END generated: jaas-deploy -->
