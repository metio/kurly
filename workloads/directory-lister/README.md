<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# directory-lister

[Directory Lister](https://github.com/DirectoryLister/DirectoryLister) — a PHP web index that lists a folder and serves its files, with search, sorting, README rendering and zip downloads. A composable `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local directoryLister = import 'github.com/metio/kurly/workloads/directory-lister/server.libsonnet';
kurly.list(directoryLister())
```

Serves on `:80`.

The listed folder is the volume mounted at `filesPath` (`/data`, which the image reads as `FILES_PATH`). kurly puts nothing in it — fill it from whatever produces the content: a sync job, an rsync sidecar, or a ReadWriteMany claim another workload writes and this one reads.

Everything else the app writes is cache: the file and view caches live beside the application code under `/var/www/html/app/cache`, so a scratch covers that path and the root filesystem stays read-only.

The content volume is ReadWriteOnce, so the stage runs one replica and is recreated rather than rolled.

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
metadata: { name: kurly, namespace: directory-lister }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-directory-lister, namespace: directory-lister }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/directory-lister, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: directory-lister }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-directory-lister, namespace: directory-lister }
spec: { sourceRef: { kind: OCIRepository, name: kurly-directory-lister } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: directory-lister, namespace: directory-lister }
spec:
  serviceAccountName: directory-lister-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/directory-lister/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-directory-lister, importPath: github.com/metio/kurly/workloads/directory-lister }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: directory-lister, namespace: directory-lister }
spec:
  serviceAccountName: directory-lister-deployer
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
        name: directory-lister
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: directory-lister }
```

<!-- END generated: jaas-deploy -->
