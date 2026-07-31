<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# calibre-web-automated

[Calibre-Web Automated](https://github.com/crocodilestick/Calibre-Web-Automated) — a self-hosted web reader and library manager for a Calibre ebook library, adding automatic ingest and format conversion on top of Calibre-Web. A `kurly.http` workload on the LinuxServer.io-based image; application config on one PersistentVolume and the Calibre library on another.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cwa = import 'github.com/metio/kurly/workloads/calibre-web-automated/server.libsonnet';
kurly.list(cwa())
```

Config at `/config` and library at `/calibre-library` on ReadWriteOnce volumes, so **one replica, recreated**. Serves the web app on `:8083`.

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
metadata: { name: kurly, namespace: calibre-web-automated }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-calibre-web-automated, namespace: calibre-web-automated }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/calibre-web-automated, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: calibre-web-automated }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-calibre-web-automated, namespace: calibre-web-automated }
spec: { sourceRef: { kind: OCIRepository, name: kurly-calibre-web-automated } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: calibre-web-automated, namespace: calibre-web-automated }
spec:
  serviceAccountName: calibre-web-automated-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/calibre-web-automated/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-calibre-web-automated, importPath: github.com/metio/kurly/workloads/calibre-web-automated }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: calibre-web-automated, namespace: calibre-web-automated }
spec:
  serviceAccountName: calibre-web-automated-deployer
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
        name: calibre-web-automated
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: calibre-web-automated }
```

<!-- END generated: jaas-deploy -->
