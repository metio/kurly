<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tvheadend

[Tvheadend](https://tvheadend.org) — a self-hosted TV streaming server and DVR (DVB, IPTV, SAT>IP) with a web UI. A `kurly.http` workload on the LinuxServer.io image (pinned by digest — Renovate maintains it); config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tvheadend = import 'github.com/metio/kurly/workloads/tvheadend/server.libsonnet';
kurly.list(tvheadend())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. HTSP streaming (`:9982`) needs an extra Service; tuners are hardware and not modelled here. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the web UI on `:9981`.

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
metadata: { name: kurly, namespace: tvheadend }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-tvheadend, namespace: tvheadend }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tvheadend, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tvheadend }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-tvheadend, namespace: tvheadend }
spec: { sourceRef: { kind: OCIRepository, name: kurly-tvheadend } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tvheadend, namespace: tvheadend }
spec:
  serviceAccountName: tvheadend-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/tvheadend/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-tvheadend, importPath: github.com/metio/kurly/workloads/tvheadend }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tvheadend, namespace: tvheadend }
spec:
  serviceAccountName: tvheadend-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: tvheadend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: tvheadend }
```

<!-- END generated: jaas-deploy -->
