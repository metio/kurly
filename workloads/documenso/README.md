<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# documenso

[Documenso](https://documenso.com) — a self-hosted, open-source alternative to DocuSign for signing documents. A `kurly.http` workload on the official image, backed by an external PostgreSQL.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local documenso = import 'github.com/metio/kurly/workloads/documenso/server.libsonnet';
kurly.list(documenso(webappUrl='https://sign.example.com'))
```

Stateless — a plain rolling Deployment. Serves on `:3000`.

**Secrets:** Documenso reads `NEXTAUTH_SECRET`, `NEXT_PRIVATE_ENCRYPTION_KEY`, `NEXT_PRIVATE_DATABASE_URL` and its SMTP settings from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. The defaults pair with a `cnpg-cluster` named `documenso-db`.

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
metadata: { name: kurly, namespace: documenso }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-documenso, namespace: documenso }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/documenso, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: documenso }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-documenso, namespace: documenso }
spec: { sourceRef: { kind: OCIRepository, name: kurly-documenso } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: documenso, namespace: documenso }
spec:
  serviceAccountName: documenso-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/documenso/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-documenso, importPath: github.com/metio/kurly/workloads/documenso }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: documenso, namespace: documenso }
spec:
  serviceAccountName: documenso-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: documenso
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: documenso }
```

<!-- END generated: jaas-deploy -->
