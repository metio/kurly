<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cadvisor

[cAdvisor](https://github.com/google/cadvisor) — per-container resource usage and
performance metrics, read straight off the node's cgroups and exported for
Prometheus. A composable `kurly.daemon` workload, because the thing it measures is
the node.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cadvisor = import 'github.com/metio/kurly/workloads/cadvisor/agent.libsonnet';

kurly.list(cadvisor(runtimeDataDir='/var/lib/containerd') + kurly.serviceMonitor())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `cadvisor` | |
| `image` | the pinned upstream image | |
| `runtimeDataDir` | none | the container runtime's data directory |
| `extraArgs` | `[]` | appended to cAdvisor's own flags |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

Serves the UI and `/metrics` on `:8080`.

## The kubelet already embeds it

Every Kubernetes node exposes cAdvisor's metrics at `/metrics/cadvisor` on the
kubelet, and a cluster scraping those needs nothing here. This stage is for the
cases where that is not enough: a node whose kubelet metrics are turned off, a
machine outside the cluster, or a deployment that wants cAdvisor's own UI and the
per-container detail the kubelet's endpoint trims. Reach for the kubelet first.

## What it reads

The node's cgroup and container state: the root filesystem to find them, `/sys`
for the cgroup hierarchy, `/var/run` for the runtime's state, and `/dev/disk` to
name block devices in the I/O metrics. All read-only, and no capability beyond
that is asked for — the paths are the privilege here.

A container runtime's data directory is **not** mounted by default. cAdvisor reads
image and layer sizes from it, and its path differs per runtime and per
distribution (`/var/lib/docker`, `/var/lib/containerd`, elsewhere on a k3s node),
so `runtimeDataDir` names it rather than guessing wrong and reporting nothing.

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
metadata: { name: kurly, namespace: cadvisor }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cadvisor, namespace: cadvisor }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cadvisor, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: cadvisor }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cadvisor, namespace: cadvisor }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cadvisor } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cadvisor, namespace: cadvisor }
spec:
  serviceAccountName: cadvisor-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local agent = import 'github.com/metio/kurly/workloads/cadvisor/agent.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(agent())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cadvisor, importPath: github.com/metio/kurly/workloads/cadvisor }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: cadvisor, namespace: cadvisor }
spec:
  serviceAccountName: cadvisor-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: agent
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: cadvisor
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: DaemonSet, name: cadvisor }
```

<!-- END generated: jaas-deploy -->
