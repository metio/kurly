<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ferron

[Ferron](https://github.com/ferronweb/ferron) — a fast, memory-safe web server written in Rust and configured in KDL. A **stateless** `kurly.http` workload on the official image: no database, no volume, no Secret.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ferron = import 'github.com/metio/kurly/workloads/ferron/server.libsonnet';
kurly.list(ferron())
```

Serves on `:8080`.

The image's own configuration listens on `:80` and writes an access and an error log to disk. This stage mounts a configuration of its own instead: an unprivileged port, so every capability stays dropped, and no log file, so the logs go to stdout where a cluster reads them and the root filesystem stays read-only with no scratch.

Out of the box it serves the placeholder site the image ships at `/var/www/ferron`. To serve your own content, mount it and point `root` at the mount — a `kurly.store` for content that outlives the pod, a `kurly.config` for a handful of files, or your own image passed as `image`. Anything the KDL grammar expresses that the parameters do not goes in as `config`, a whole document taken verbatim; `port` still governs the container and Service ports, so it must match what that document binds.

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
metadata: { name: kurly, namespace: ferron }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ferron, namespace: ferron }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ferron, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ferron }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ferron, namespace: ferron }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ferron } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ferron, namespace: ferron }
spec:
  serviceAccountName: ferron-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ferron/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ferron, importPath: github.com/metio/kurly/workloads/ferron }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ferron, namespace: ferron }
spec:
  serviceAccountName: ferron-deployer
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
        name: ferron
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ferron }
```

<!-- END generated: jaas-deploy -->
