<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tempo

[Grafana Tempo](https://grafana.com/oss/tempo/) — a distributed **traces**
backend — as a [tempo-operator](https://grafana.com/docs/tempo/latest/setup/operator/)
`TempoStack` custom resource. One CR reconciles the whole topology — distributor,
ingester, querier, query-frontend, and compactor — over object storage. Like
[loki](../loki/) (and the same shape as its `LokiStack`), this authors the CR
directly; the operator owns the Deployments, StatefulSets, config, and Services.

It completes the observability trio alongside [prometheus](../prometheus/) +
[thanos](../thanos/) (metrics) and [loki](../loki/) (logs): point the
[otel-collector](../otel-collector/) at it to store spans, and add a Tempo
datasource in [grafana](../grafana/) to read them.

**Prerequisite:** the tempo-operator (its CRDs and controller) must be installed.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tempo = import 'github.com/metio/kurly/workloads/tempo/server.libsonnet';

kurly.list(tempo(storageSecret='tempo-s3', storageClass='fast'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `tempo` | |
| `storageSecret` | `tempo-storage` | the object-storage Secret you create — see below |
| `storageSize` | `10Gi` | the per-component PVC (ingester WAL, local cache) |
| `storageClass` | cluster default | |
| `spec` | `{}` | extra `TempoStack` spec fields, merged verbatim |

The operator picks the Tempo image from the `TempoStack` version, so there is none
to pin here. Per-component replicas and resources, `replicationFactor`, retention,
and multi-tenancy live under the `spec` escape (the operator's schema is deep):

```jsonnet
tempo(spec={
  replicationFactor: 2,
  template: { ingester: { replicas: 3 }, compactor: { replicas: 1 } },
})
```

## Object storage (the seaweedfs pairing)

Tempo keeps its trace blocks in **object storage**, named by a Secret you create —
the operator does not. This is where it pairs with the [seaweedfs](../seaweedfs/)
workload: point the Secret at its S3 gateway.

```shell
kubectl create secret generic tempo-storage \
  --from-literal=bucket=tempo \
  --from-literal=endpoint=http://seaweedfs-0.seaweedfs-headless.storage.svc:8333 \
  --from-literal=access_key_id=tempo \
  --from-literal=access_key_secret=temposecret
```

Create the `tempo` bucket on SeaweedFS first. Rather than applying that Secret by
hand, fill it from your secrets store with `kurly.externalSecret('tempo-storage', …)`
— see [Secrets](../../#secrets).

## Wiring the pipeline

- **Ingest:** send spans (OTLP) to the operator's distributor Service,
  `tempo-<name>-distributor`, on `:4317` (gRPC) or `:4318` (HTTP). The
  otel-collector's `otlp` exporter points here.
- **Read:** add a Tempo datasource in Grafana at
  `http://tempo-<name>-query-frontend.<namespace>.svc:3200`.

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
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: tempo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-tempo, namespace: tempo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tempo, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tempo }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-tempo, namespace: tempo }
spec: { sourceRef: { kind: OCIRepository, name: kurly-tempo } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tempo, namespace: tempo }
spec:
  serviceAccountName: tempo-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/tempo/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-tempo, importPath: github.com/metio/kurly/workloads/tempo }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tempo, namespace: tempo }
spec:
  serviceAccountName: tempo-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: tempo
```

<!-- END generated: jaas-deploy -->
