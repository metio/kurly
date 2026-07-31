<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mailpit

[Mailpit](https://mailpit.axllent.org) — a self-hosted email- and SMTP-testing tool: it catches every message your apps send and shows them in a web UI, with a real SMTP sink and an API. A `kurly.http` workload on the official image, listening on **two ports** (the web UI/API and the SMTP sink) via `kurly.extraPort`; message store (SQLite) on a PersistentVolume under `/data`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mailpit = import 'github.com/metio/kurly/workloads/mailpit/server.libsonnet';
kurly.list(mailpit())
```

Store at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the web UI and API on `:8025` and accepts SMTP on `:1025` — point your apps' SMTP client at the Service on port 1025, and compose an exposure onto the web port.

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
metadata: { name: kurly, namespace: mailpit }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mailpit, namespace: mailpit }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mailpit, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mailpit }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mailpit, namespace: mailpit }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mailpit } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mailpit, namespace: mailpit }
spec:
  serviceAccountName: mailpit-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mailpit/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mailpit, importPath: github.com/metio/kurly/workloads/mailpit }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mailpit, namespace: mailpit }
spec:
  serviceAccountName: mailpit-deployer
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
        name: mailpit
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mailpit }
```

<!-- END generated: jaas-deploy -->
