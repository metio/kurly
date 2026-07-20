<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nginx-proxy-manager

[Nginx Proxy Manager](https://nginxproxymanager.com) — a self-hosted reverse-proxy with a web UI, free Let's Encrypt certificates, access lists and custom nginx config. A `kurly.http` workload on the official image; SQLite database and config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local npm = import 'github.com/metio/kurly/workloads/nginx-proxy-manager/server.libsonnet';
kurly.list(npm())
```

The reverse proxy listens on `:80`/`:443` — add a Service (usually a LoadBalancer) for them. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. The admin UI serves on `:81`.

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
metadata: { name: kurly, namespace: nginx-proxy-manager }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-nginx-proxy-manager, namespace: nginx-proxy-manager }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/nginx-proxy-manager, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: nginx-proxy-manager }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-nginx-proxy-manager, namespace: nginx-proxy-manager }
spec: { sourceRef: { kind: OCIRepository, name: kurly-nginx-proxy-manager } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: nginx-proxy-manager, namespace: nginx-proxy-manager }
spec:
  serviceAccountName: nginx-proxy-manager-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/nginx-proxy-manager/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-nginx-proxy-manager, importPath: github.com/metio/kurly/workloads/nginx-proxy-manager }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: nginx-proxy-manager, namespace: nginx-proxy-manager }
spec:
  serviceAccountName: nginx-proxy-manager-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: nginx-proxy-manager
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: nginx-proxy-manager }
```

<!-- END generated: jaas-deploy -->
