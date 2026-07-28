<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# projectsend

[ProjectSend](https://www.projectsend.org) — a self-hosted, private file-sharing app: upload files and assign them to specific clients. A `kurly.http` workload on the LinuxServer.io image, backed by an external MySQL/MariaDB, with config and uploads on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local projectsend = import 'github.com/metio/kurly/workloads/projectsend/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';
kurly.list([
  mysql(name='projectsend-db'),
  projectsend(),
])
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Config and uploads at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.

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
metadata: { name: kurly, namespace: projectsend }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-projectsend, namespace: projectsend }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/projectsend, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: projectsend }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-projectsend, namespace: projectsend }
spec: { sourceRef: { kind: OCIRepository, name: kurly-projectsend } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: projectsend, namespace: projectsend }
spec:
  serviceAccountName: projectsend-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/projectsend/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-projectsend, importPath: github.com/metio/kurly/workloads/projectsend }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: projectsend, namespace: projectsend }
spec:
  serviceAccountName: projectsend-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: projectsend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: projectsend }
```

<!-- END generated: jaas-deploy -->
