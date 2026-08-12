<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kubetail

[Kubetail](https://www.kubetail.com) — follow the logs of many pods at once,
across deployments and namespaces, with search and live follow. Three composable
stages.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dashboard = import 'github.com/metio/kurly/workloads/kubetail/dashboard.libsonnet';
local api = import 'github.com/metio/kurly/workloads/kubetail/cluster-api.libsonnet';
local agent = import 'github.com/metio/kurly/workloads/kubetail/cluster-agent.libsonnet';

kurly.list([dashboard(), api(), agent()])
```

| Stage | Kind | Serves |
|---|---|---|
| `dashboard` | http | the browser front end, `:8080` |
| `cluster-api` | http | internal API, `:8080` |
| `cluster-agent` | daemon | gRPC `:50051`, one per node |

## Deploy all three

The dashboard is the front end, cluster-api is what it asks, and the agent reads
the log files off each node. A dashboard alone lists workloads and shows no logs,
which looks like a broken cluster rather than a missing component.

## The grants are split on purpose

The dashboard reads only what workloads **exist**. `pods/log` — every line every
workload on the cluster prints — belongs to cluster-api. That is what lets you
expose the dashboard while cluster-api stays inside.

Whoever reaches the dashboard reads whatever the cluster prints, which routinely
includes tokens, query parameters and personal data nobody meant to publish. Put
authentication in front of it.

## Why a separate agent at all

The apiserver can serve pod logs, but reading the files directly is what makes
searching and following many pods at once cheap, instead of opening one apiserver
stream per pod. The cost is a DaemonSet with a hostPath — mounted **read-only**,
because an agent that could write those files could alter the record it exists to
serve.

A DaemonSet publishes no Service of its own, and cluster-api needs to reach *every*
agent rather than one of them, so a headless Service resolving to all their
addresses is rendered beside it.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
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
metadata: { name: kurly, namespace: kubetail }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-kubetail, namespace: kubetail }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/kubetail, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: kubetail }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-kubetail, namespace: kubetail }
spec: { sourceRef: { kind: OCIRepository, name: kurly-kubetail } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: kubetail-cluster-agent, namespace: kubetail }
spec:
  serviceAccountName: kubetail-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local cluster_agent = import 'github.com/metio/kurly/workloads/kubetail/cluster-agent.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(cluster_agent())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-kubetail, importPath: github.com/metio/kurly/workloads/kubetail }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: kubetail-cluster-api, namespace: kubetail }
spec:
  serviceAccountName: kubetail-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local cluster_api = import 'github.com/metio/kurly/workloads/kubetail/cluster-api.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(cluster_api())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-kubetail, importPath: github.com/metio/kurly/workloads/kubetail }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: kubetail-dashboard, namespace: kubetail }
spec:
  serviceAccountName: kubetail-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local dashboard = import 'github.com/metio/kurly/workloads/kubetail/dashboard.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(dashboard())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-kubetail, importPath: github.com/metio/kurly/workloads/kubetail }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: kubetail, namespace: kubetail }
spec:
  serviceAccountName: kubetail-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: cluster-agent
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: kubetail-cluster-agent
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: DaemonSet, name: kubetail-cluster-agent }
    - name: cluster-api
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: kubetail-cluster-api
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: kubetail-cluster-api }
    - name: dashboard
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: kubetail-dashboard
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: kubetail-dashboard }
```

<!-- END generated: jaas-deploy -->
