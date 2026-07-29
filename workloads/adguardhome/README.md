<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# adguardhome

[AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) — a self-hosted, network-wide
DNS ad- and tracker-blocker with a friendly web UI, an alternative to Pi-hole. A plain
composable `kurly.http` workload on the official image; its configuration and runtime data
live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local adguardhome = import 'github.com/metio/kurly/workloads/adguardhome/server.libsonnet';
kurly.list(adguardhome())
```

AdGuard Home answers **DNS on `:53`** (TCP and UDP), separate ports this HTTP workload does
not expose — add a Service for `:53` (usually a LoadBalancer) so clients can point their
resolver at it. The config and work directory both live under `/opt/adguardhome`, so a
single volume persists everything; on a ReadWriteOnce volume this is **one replica,
recreated**. The admin UI (first-run setup wizard) serves on `:3000`.

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
metadata: { name: kurly, namespace: adguardhome }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-adguardhome, namespace: adguardhome }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/adguardhome, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: adguardhome }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-adguardhome, namespace: adguardhome }
spec: { sourceRef: { kind: OCIRepository, name: kurly-adguardhome } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: adguardhome, namespace: adguardhome }
spec:
  serviceAccountName: adguardhome-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/adguardhome/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-adguardhome, importPath: github.com/metio/kurly/workloads/adguardhome }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: adguardhome, namespace: adguardhome }
spec:
  serviceAccountName: adguardhome-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: adguardhome
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: adguardhome }
```

<!-- END generated: jaas-deploy -->
