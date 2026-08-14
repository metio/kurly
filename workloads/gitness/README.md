<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gitness

[Harness Open Source](https://github.com/harness/gitness) — the project Gitness was
renamed to. Git repositories, pull requests, an artifact registry and a web interface in
one binary, with SQLite underneath, so it needs no database beside it.

A plain composable `kurly.http` workload. The database, the repositories and the registry
blobs share one volume, which makes this a **single writer**: one replica, recreated
rather than rolled.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gitness = import 'github.com/metio/kurly/workloads/gitness/server.libsonnet';

kurly.list(
  gitness(url='https://git.example.com')
  + kurly.expose.gateway('git.example.com', 'public')
)
```

## Pipelines and Gitspaces need a Docker daemon

The binary drives a Docker API to run pipeline steps and development environments, and
there is no daemon inside the pod. Repositories, pull requests, the registry and the web
interface all work; starting a pipeline reports that Docker is unreachable. `gitspaces`
defaults to off so the half that cannot work does not advertise itself.

## Two protocols, one Service

`:3000` is the web interface and API. `:3022` is git-over-SSH, published as the extra
port `ssh` — a raw TCP protocol that needs a TCP route, so an HTTP exposure publishes the
web interface and leaves SSH cloning unreachable.

## It phones home unless you say otherwise

The image ships with usage reporting enabled to an endpoint at the project. `metrics`
defaults to off here and writes the variable that keeps it off.

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
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: gitness }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gitness, namespace: gitness }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gitness, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gitness }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gitness, namespace: gitness }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gitness } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gitness, namespace: gitness }
spec:
  serviceAccountName: gitness-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gitness/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gitness, importPath: github.com/metio/kurly/workloads/gitness }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gitness, namespace: gitness }
spec:
  serviceAccountName: gitness-deployer
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
        name: gitness
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gitness }
```

<!-- END generated: jaas-deploy -->
