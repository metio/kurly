<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gpustack

[GPUStack](https://github.com/gpustack/gpustack) — a manager for a GPU cluster. It holds
the model catalogue, schedules inference onto workers, and serves an OpenAI-compatible
API in front of whatever they are running.

This carries the **server**, which needs no GPU of its own. A plain composable
`kurly.http` workload; the database and model metadata share one volume, which makes it a
**single writer**: one replica, recreated rather than rolled.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gpustack = import 'github.com/metio/kurly/workloads/gpustack/server.libsonnet';

kurly.list(
  gpustack()
  + kurly.expose.gateway('models.example.com', 'public')
)
```

## The workers are not this

A worker is where a model actually runs, and upstream starts one with `--privileged`, the
host's network, the host's Docker socket and the NVIDIA runtime. That combination is a
node agent rather than a tenant's deployment, and this recipe deliberately does not
package it. Run the server here and join workers to it.

## The first start generates the credentials

The server writes an initial admin password and a worker join token under
`/var/lib/gpustack` on its first boot. A deployment that never reads them out of the
volume can neither log in nor join a worker, so plan to fetch them once the pod is up.

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
metadata: { name: kurly, namespace: gpustack }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gpustack, namespace: gpustack }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gpustack, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gpustack }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gpustack, namespace: gpustack }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gpustack } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gpustack, namespace: gpustack }
spec:
  serviceAccountName: gpustack-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gpustack/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gpustack, importPath: github.com/metio/kurly/workloads/gpustack }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gpustack, namespace: gpustack }
spec:
  serviceAccountName: gpustack-deployer
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
        name: gpustack
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gpustack }
```

<!-- END generated: jaas-deploy -->
