<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# blocky

[blocky](https://0xerr0r.github.io/blocky/latest/) — a fast, lightweight DNS proxy and ad-blocker for a local network, without a database or a web console. A `kurly.http` workload on the official image; its only state is the config.yml it starts from, rendered as a ConfigMap.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local blocky = import 'github.com/metio/kurly/workloads/blocky/server.libsonnet';
kurly.list(blocky())
```

blocky answers **DNS on `:53`** (TCP/UDP) — add a Service for it (usually a LoadBalancer). Its REST API and Prometheus metrics serve on `:4000` — compose an exposure onto it if you want either. No Secret: nothing in blocky's config is a credential. It keeps no database, so it is stateless and safe at any replica count.

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
metadata: { name: kurly, namespace: blocky }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-blocky, namespace: blocky }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/blocky, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: blocky }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-blocky, namespace: blocky }
spec: { sourceRef: { kind: OCIRepository, name: kurly-blocky } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: blocky, namespace: blocky }
spec:
  serviceAccountName: blocky-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/blocky/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-blocky, importPath: github.com/metio/kurly/workloads/blocky }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: blocky, namespace: blocky }
spec:
  serviceAccountName: blocky-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: blocky
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: blocky }
```

<!-- END generated: jaas-deploy -->
