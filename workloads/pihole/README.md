<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pihole

[Pi-hole](https://pi-hole.net) — a self-hosted, network-wide DNS sinkhole that blocks ads and trackers, with a web admin dashboard. A `kurly.http` workload on the official image; config and query database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pihole = import 'github.com/metio/kurly/workloads/pihole/server.libsonnet';
kurly.list(pihole())
```

Pi-hole answers **DNS on `:53`** (TCP/UDP) — add a Service for it (usually a LoadBalancer). The admin password (`FTLCONF_webserver_api_password`) comes from a Secret via `envFrom` — kurly authors **no Secret**. Config at `/etc/pihole` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the admin dashboard on `:80`.

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
metadata: { name: kurly, namespace: pihole }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pihole, namespace: pihole }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pihole, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pihole }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pihole, namespace: pihole }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pihole } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pihole, namespace: pihole }
spec:
  serviceAccountName: pihole-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pihole/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pihole, importPath: github.com/metio/kurly/workloads/pihole }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pihole, namespace: pihole }
spec:
  serviceAccountName: pihole-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: pihole
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pihole }
```

<!-- END generated: jaas-deploy -->
