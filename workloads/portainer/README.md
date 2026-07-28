<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# portainer

[Portainer CE](https://www.portainer.io) — a self-hosted management UI for Docker and Kubernetes. A `kurly.http` workload on the official image; its database and settings on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local portainer = import 'github.com/metio/kurly/workloads/portainer/server.libsonnet';
kurly.list(portainer(serviceAccountName='portainer'))
```

Database at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the UI on `:9000`.

To administer the cluster it runs in, Portainer needs a ServiceAccount bound to a ClusterRole (cluster-admin for full control). kurly authors no RBAC; create the ServiceAccount and binding yourself and pass its name as `serviceAccountName`.

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
metadata: { name: kurly, namespace: portainer }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-portainer, namespace: portainer }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/portainer, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: portainer }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-portainer, namespace: portainer }
spec: { sourceRef: { kind: OCIRepository, name: kurly-portainer } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: portainer, namespace: portainer }
spec:
  serviceAccountName: portainer-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/portainer/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-portainer, importPath: github.com/metio/kurly/workloads/portainer }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: portainer, namespace: portainer }
spec:
  serviceAccountName: portainer-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: portainer
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: portainer }
```

<!-- END generated: jaas-deploy -->
