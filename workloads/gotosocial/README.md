<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gotosocial

[GoToSocial](https://gotosocial.org) — a lightweight, self-hosted ActivityPub/Fediverse
social server, an alternative to Mastodon that federates with it. A plain composable
`kurly.http` workload on the official image; with the default SQLite backend its database
and stored media live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gotosocial = import 'github.com/metio/kurly/workloads/gotosocial/server.libsonnet';
kurly.list(gotosocial(host='social.example.com'))
```

The `host` (the domain in every account's `@handle`) is **fixed at first run and cannot be
changed later** — set it deliberately. Point GoToSocial at an external PostgreSQL
(`GTS_DB_TYPE=postgres` plus the `GTS_DB_*` connection) to scale past SQLite. Data at
`/gotosocial/storage` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on
`:8080`.

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
metadata: { name: kurly, namespace: gotosocial }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gotosocial, namespace: gotosocial }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gotosocial, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gotosocial }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gotosocial, namespace: gotosocial }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gotosocial } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gotosocial, namespace: gotosocial }
spec:
  serviceAccountName: gotosocial-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gotosocial/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gotosocial, importPath: github.com/metio/kurly/workloads/gotosocial }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gotosocial, namespace: gotosocial }
spec:
  serviceAccountName: gotosocial-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: gotosocial
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gotosocial }
```

<!-- END generated: jaas-deploy -->
