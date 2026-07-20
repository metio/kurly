<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ejabberd

[ejabberd](https://github.com/processone/ejabberd) — a robust, scalable
XMPP/messaging server. A plain composable `kurly.http` workload on the official
community image that keeps its Mnesia database and uploads on a PersistentVolume,
so it needs no external database by default.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ejabberd = import 'github.com/metio/kurly/workloads/ejabberd/server.libsonnet';

kurly.list(ejabberd())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ejabberd` | |
| `image` | `docker.io/ejabberd/ecs:26.04` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the Mnesia database volume |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves XMPP client (`:5222`), server-to-server (`:5269`), and the admin/HTTP API
(`:5280`). Route the XMPP ports as TCP through a LoadBalancer or Gateway TCPRoute,
and expose `:5280` for the admin UI.

## Configuration

ejabberd reads `ejabberd.yml` from `/home/ejabberd/conf`. Mount it with
`kurly.config` (host, admin, listeners); any credentials it references belong in a
Secret (kurly mints none).

## Persistence

The Mnesia database lives on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two pods off the files. Clustering ejabberd
across pods needs shared Mnesia or an external database — beyond this recipe's
default.

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
metadata: { name: kurly, namespace: ejabberd }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ejabberd, namespace: ejabberd }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ejabberd, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ejabberd }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ejabberd, namespace: ejabberd }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ejabberd } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ejabberd, namespace: ejabberd }
spec:
  serviceAccountName: ejabberd-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ejabberd/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ejabberd, importPath: github.com/metio/kurly/workloads/ejabberd }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ejabberd, namespace: ejabberd }
spec:
  serviceAccountName: ejabberd-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: ejabberd
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ejabberd }
```

<!-- END generated: jaas-deploy -->
