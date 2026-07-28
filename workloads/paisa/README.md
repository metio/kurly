<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# paisa

[Paisa](https://paisa.fyi/) — a plain-text, double-entry personal finance manager
built on ledger/beancount journals. A plain composable `kurly.http` workload that
reads its configuration and journal from a PersistentVolume, so it needs no
external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local paisa = import 'github.com/metio/kurly/workloads/paisa/server.libsonnet';

kurly.list(paisa())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `paisa` | |
| `image` | `ghcr.io/ananthakumaran/paisa:0.7.4` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the data volume (`/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI on `:7500` — compose an exposure onto it:

```jsonnet
kurly.list([
  paisa()
  + kurly.expose.ownGateway('finance.example.com', 'istio', tls='paisa-tls'),
  kurly.certificate('paisa-tls', ['finance.example.com'], 'letsencrypt-prod'),
])
```

## Data

Paisa runs from `/data` and reads `paisa.yaml` and the journal it references from
there. Provide them on the volume before first use. The journal and its generated
database live on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: paisa }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-paisa, namespace: paisa }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/paisa, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: paisa }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-paisa, namespace: paisa }
spec: { sourceRef: { kind: OCIRepository, name: kurly-paisa } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: paisa, namespace: paisa }
spec:
  serviceAccountName: paisa-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/paisa/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-paisa, importPath: github.com/metio/kurly/workloads/paisa }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: paisa, namespace: paisa }
spec:
  serviceAccountName: paisa-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: paisa
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: paisa }
```

<!-- END generated: jaas-deploy -->
