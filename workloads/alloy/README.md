<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# alloy

[Grafana Alloy](https://grafana.com/oss/alloy) — an OpenTelemetry collector
distribution: it scrapes metrics, tails logs and receives traces, then forwards
them to whatever stores them. A composable `kurly.daemon` workload.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local alloy = import 'github.com/metio/kurly/workloads/alloy/agent.libsonnet';

kurly.list(alloy(namespace='alloy', config=|||
  prometheus.remote_write "default" {
    endpoint { url = "http://mimir:9009/api/v1/push" }
  }
|||))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `alloy` | |
| `image` | the pinned upstream image | |
| `namespace` | `alloy` | where the ServiceAccount lives — required |
| `config` | a logging block | Alloy's own configuration language, verbatim |
| `resources` / `env` / `labels` / `annotations` | | |

## Alloy stores nothing

It is the collector half of an observability stack, so a deployment needs a
backend for the metrics, logs or traces it forwards — kurly carries Prometheus,
Loki, Tempo and Thanos for exactly that. An Alloy with no destination configured
runs happily and drops everything.

## The configuration is a program, not a document

Alloy's config is written in its own language, with components wired to each other
by reference. There is no useful default beyond a self-monitoring skeleton, so
`config` takes that language verbatim rather than pretending a YAML shape
underneath.

## What it reads

The apiserver, to discover pods, services and endpoints across the cluster — a
read-only cluster-wide grant, and what makes it a collector rather than a static
scraper. The node's `/var/log` is mounted **read-only**: an agent that could write
the logs could rewrite the record it exists to ship.

Its HTTP server binds every interface, because the kubelet's probe arrives from
outside the pod's loopback. A daemon publishes no Service, so nothing reaches the
built-in UI by default — adding one publishes the component graph and the values
flowing through it.

The storage path is a write-ahead buffer, not a database. On the pod it survives a
container restart and not a reschedule, which for a metrics agent means a gap
rather than a lost record.

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
metadata: { name: kurly, namespace: alloy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-alloy, namespace: alloy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/alloy, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: alloy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-alloy, namespace: alloy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-alloy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: alloy, namespace: alloy }
spec:
  serviceAccountName: alloy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local agent = import 'github.com/metio/kurly/workloads/alloy/agent.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(agent())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-alloy, importPath: github.com/metio/kurly/workloads/alloy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: alloy, namespace: alloy }
spec:
  serviceAccountName: alloy-deployer
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
        name: alloy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: DaemonSet, name: alloy }
```

<!-- END generated: jaas-deploy -->
