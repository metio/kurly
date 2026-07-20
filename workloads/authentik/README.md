<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# authentik

[authentik](https://goauthentik.io) — a self-hosted identity provider and SSO: OAuth2, SAML,
LDAP, forward-auth and more. It runs as **two workloads** on the same image — a web/API `server`
and a background `worker` — backed by an external PostgreSQL and Redis.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/authentik/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/authentik/worker.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='authentik-db', database='authentik')).items,
  kurly.list(server()).items,
  kurly.list(worker()).items,
]))
```

Both stages read the PostgreSQL/Redis connection (`AUTHENTIK_POSTGRESQL__*`,
`AUTHENTIK_REDIS__*`) and `AUTHENTIK_SECRET_KEY` from a shared Secret (`authentik-secrets`) via
`envFrom` — kurly authors **no Secret**. The server serves on `:9000`; the worker has no Service.
Stateless (state lives in PostgreSQL/Redis).

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: authentik }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-authentik, namespace: authentik }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/authentik, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: authentik }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-authentik, namespace: authentik }
spec: { sourceRef: { kind: OCIRepository, name: kurly-authentik } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: authentik-server, namespace: authentik }
spec:
  serviceAccountName: authentik-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/authentik/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-authentik, importPath: github.com/metio/kurly/workloads/authentik }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: authentik-worker, namespace: authentik }
spec:
  serviceAccountName: authentik-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local worker = import 'github.com/metio/kurly/workloads/authentik/worker.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(worker())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-authentik, importPath: github.com/metio/kurly/workloads/authentik }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: authentik, namespace: authentik }
spec:
  serviceAccountName: authentik-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: authentik-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: authentik-server }
    - name: worker
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: authentik-worker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: authentik-worker }
```

<!-- END generated: jaas-deploy -->
