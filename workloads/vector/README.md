<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# vector

[Vector](https://vector.dev) — a pipeline for logs, metrics and traces: it
collects them, reshapes them with a transform language, and sends them wherever
they are meant to go. A composable `kurly.daemon` workload, because collecting a
node's container logs means reading them off that node.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local vector = import 'github.com/metio/kurly/workloads/vector/agent.libsonnet';

kurly.list(vector(namespace='vector', sinks={
  loki: {
    type: 'loki',
    inputs: ['kubernetes_logs'],
    endpoint: 'http://loki:3100',
    encoding: { codec: 'json' },
  },
}))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `vector` | |
| `image` | the pinned upstream image | |
| `namespace` | `vector` | where the ServiceAccount lives — required |
| `sinks` | a console sink | where the collected data goes |
| `sources` | `{}` | added to the `kubernetes_logs` source |
| `transforms` | `{}` | Vector Remap Language stages |
| `dataDir` | none | a node path for the read checkpoints |
| `resources` / `env` / `labels` / `annotations` | | |

## The default sink prints to stdout, which is not a pipeline

The `kubernetes_logs` source is configured for you; where the data goes is the
decision only the deployment can make, and there is no honest default for it. So
the default sink is a console one — the agent starts, and what it collects is
visibly going nowhere useful, which is a better failure than buffering into a
void. Passing an empty `sinks` is refused outright, because that one is not a
mistake anybody makes on purpose.

## What it reads

Every container's logs on the node, from `/var/log`, mounted **read-only**: an
agent that could write them could rewrite the record it exists to ship. It also
asks the apiserver for the pod metadata to label the lines with, which is the
cluster-wide grant — read-only on pods, namespaces and nodes.

## State is the checkpoint file

Vector remembers how far it read in each log file under its data directory. On the
pod that survives a container restart but not a reschedule, so a moved agent
re-reads what the node still has. `dataDir` puts the checkpoints on the node
instead, which makes them survive the pod at the cost of writing to it.

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
metadata: { name: kurly, namespace: vector }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-vector, namespace: vector }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/vector, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: vector }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-vector, namespace: vector }
spec: { sourceRef: { kind: OCIRepository, name: kurly-vector } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: vector, namespace: vector }
spec:
  serviceAccountName: vector-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local agent = import 'github.com/metio/kurly/workloads/vector/agent.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(agent())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-vector, importPath: github.com/metio/kurly/workloads/vector }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: vector, namespace: vector }
spec:
  serviceAccountName: vector-deployer
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
        name: vector
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: DaemonSet, name: vector }
```

<!-- END generated: jaas-deploy -->
