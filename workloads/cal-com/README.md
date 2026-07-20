<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cal-com

[Cal.com](https://cal.com) — a self-hosted, open-source scheduling platform, an alternative to Calendly. A `kurly.http` workload on the official image, backed by an external PostgreSQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local calcom = import 'github.com/metio/kurly/workloads/cal-com/server.libsonnet';
kurly.list(calcom(webappUrl='https://cal.example.com'))
```

Stateless — a plain rolling Deployment. Serves on `:3000`.

**Secrets:** Cal.com reads `DATABASE_URL`, `NEXTAUTH_SECRET`, `CALENDSO_ENCRYPTION_KEY` and its integration credentials from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. The defaults pair with a `cnpg-cluster` named `cal-com-db`.

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
metadata: { name: kurly, namespace: cal-com }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cal-com, namespace: cal-com }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cal-com, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: cal-com }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cal-com, namespace: cal-com }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cal-com } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cal-com, namespace: cal-com }
spec:
  serviceAccountName: cal-com-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/cal-com/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cal-com, importPath: github.com/metio/kurly/workloads/cal-com }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: cal-com, namespace: cal-com }
spec:
  serviceAccountName: cal-com-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: cal-com
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: cal-com }
```

<!-- END generated: jaas-deploy -->
