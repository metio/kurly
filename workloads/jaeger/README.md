<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# jaeger

[Jaeger](https://www.jaegertracing.io/) — distributed tracing: it receives spans
over OTLP, stores them and serves the UI that reconstructs a request's path
through a system. A plain composable `kurly.http` workload running the Jaeger v2
binary with its built-in all-in-one configuration.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local jaeger = import 'github.com/metio/kurly/workloads/jaeger/server.libsonnet';

kurly.list(jaeger())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `jaeger` | |
| `image` | the pinned upstream image | |
| `config` | none | a Jaeger v2 (OpenTelemetry Collector) configuration |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

Serves the UI on `:16686` and accepts OTLP on `:4317` (gRPC) and `:4318` (HTTP) —
compose an exposure onto the UI, and point instrumented workloads at the Service's
OTLP ports.

## Traces are in memory

The shipped configuration keeps spans in a bounded in-process store, which is what
makes this one container with no dependencies — and it means a rollout, an
eviction or an OOM kill loses everything collected so far. That is a fair trade
for development and for debugging a staging cluster, and it is not a trace
archive. Anything that has to keep traces needs a storage backend
(Elasticsearch, OpenSearch, Cassandra, or the badger file store) configured
through `config`, with the volume or the backend to go with it.

One replica for the same reason: each pod holds its own traces, so a query
answered by one pod cannot see spans the other received.

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
metadata: { name: kurly, namespace: jaeger }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-jaeger, namespace: jaeger }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/jaeger, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: jaeger }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-jaeger, namespace: jaeger }
spec: { sourceRef: { kind: OCIRepository, name: kurly-jaeger } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: jaeger, namespace: jaeger }
spec:
  serviceAccountName: jaeger-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/jaeger/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-jaeger, importPath: github.com/metio/kurly/workloads/jaeger }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: jaeger, namespace: jaeger }
spec:
  serviceAccountName: jaeger-deployer
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
        name: jaeger
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: jaeger }
```

<!-- END generated: jaas-deploy -->
