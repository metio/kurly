<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# fluidd

[Fluidd](https://github.com/fluidd-core/fluidd) — the web interface for Klipper-based 3D printers: job queue, temperatures, console and file management. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local fluidd = import 'github.com/metio/kurly/workloads/fluidd/server.libsonnet';
kurly.list(fluidd())
```

Serves on `:80`.

Fluidd is only the interface: it talks to a Moonraker API running beside Klipper on the printer's host, which a cluster does not provide. The browser makes that connection, not the pod, so the endpoint is configured by whoever opens the page.

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
metadata: { name: kurly, namespace: fluidd }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-fluidd, namespace: fluidd }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/fluidd, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: fluidd }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-fluidd, namespace: fluidd }
spec: { sourceRef: { kind: OCIRepository, name: kurly-fluidd } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: fluidd, namespace: fluidd }
spec:
  serviceAccountName: fluidd-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/fluidd/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-fluidd, importPath: github.com/metio/kurly/workloads/fluidd }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: fluidd, namespace: fluidd }
spec:
  serviceAccountName: fluidd-deployer
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
        name: fluidd
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: fluidd }
```

<!-- END generated: jaas-deploy -->
