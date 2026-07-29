<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# technitium

[Technitium DNS Server](https://technitium.com/dns/) — a self-hosted, privacy-focused DNS server with ad-blocking, DNS-over-HTTPS/TLS and a full web console. A `kurly.http` workload on the official image; config and zones on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local technitium = import 'github.com/metio/kurly/workloads/technitium/server.libsonnet';
kurly.list(technitium())
```

Answers **DNS on `:53`** (TCP/UDP) — add a Service for it (usually a LoadBalancer). The admin password (`DNS_SERVER_ADMIN_PASSWORD`) comes from a Secret via `envFrom` — kurly authors **no Secret**. Config at `/etc/dns` on a ReadWriteOnce volume, so **one replica, recreated**. The web console serves on `:5380`.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: technitium }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-technitium, namespace: technitium }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/technitium, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: technitium }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-technitium, namespace: technitium }
spec: { sourceRef: { kind: OCIRepository, name: kurly-technitium } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: technitium, namespace: technitium }
spec:
  serviceAccountName: technitium-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/technitium/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-technitium, importPath: github.com/metio/kurly/workloads/technitium }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: technitium, namespace: technitium }
spec:
  serviceAccountName: technitium-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: technitium
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: technitium }
```

<!-- END generated: jaas-deploy -->
