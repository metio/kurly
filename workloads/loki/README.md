<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# loki

[Grafana Loki](https://grafana.com/oss/loki/) in **microservices mode** as a
[loki-operator](https://loki-operator.dev/) `LokiStack` custom resource. One CR
reconciles the whole distributed topology — distributor, ingester, querier,
query-frontend, compactor, index-gateway, and gateway — and `size` chooses the
replica scaling. Like [cnpg-cluster](../cnpg-cluster/) and
[prometheus](../prometheus/), this authors the CR directly; the operator owns the
Deployments, StatefulSets, config, and the memberlist ring.

**Prerequisite:** the loki-operator (its CRDs and controller) must be installed.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local loki = import 'github.com/metio/kurly/workloads/loki/server.libsonnet';

kurly.list(loki(size='1x.small', storageSecret='loki-s3', storageClass='fast'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `loki` | |
| `size` | `1x.demo` | `1x.demo` / `1x.pico` / `1x.extra-small` / `1x.small` / `1x.medium` |
| `storageSecret` | `loki-storage` | the object-storage Secret you create — see below |
| `storageClass` | cluster default | for the components' PVCs |
| `schemaVersion` / `schemaEffectiveDate` | `v13` / `2024-01-01` | the index schema |
| `spec` | `{}` | extra `LokiStack` spec fields, merged verbatim |

`size` is the operator's t-shirt scaling: `1x.demo` is the smallest (single
replicas, minimal resources) and the right one for a test cluster; production
wants `1x.extra-small` or larger.

## Object storage (the seaweedfs pairing)

Loki keeps its chunks and index in **object storage**, named by a Secret you
create — the operator does not. This is where it pairs with the
[seaweedfs](../seaweedfs/) workload: point the Secret at its S3 gateway.

```shell
kubectl create secret generic loki-storage \
  --from-literal=bucketnames=loki \
  --from-literal=endpoint=http://seaweedfs-0.seaweedfs-headless.storage.svc:8333 \
  --from-literal=access_key_id=loki \
  --from-literal=access_key_secret=lokisecret \
  --from-literal=region=us-east-1
```

Create the `loki` bucket on SeaweedFS first. Reach Loki at the operator's gateway
Service, `lokistack-gateway-http` (or the per-component Services for direct push
and query).

Rather than applying that Secret by hand, fill it from your secrets store with
`kurly.externalSecret('loki-storage', …)` — see [Secrets](../../#secrets).

## Air-gapped / private registry

The `LokiStack` CR carries **no image** — the loki-operator chooses the Loki and
gateway images itself, so `kurly.mirror` (which rewrites images in the rendered
manifests) has nothing to redirect here. Loki's air-gap knob is on the
**operator**, not the CR: the operator reads the images from environment
variables, so install it pointing at your mirror —

```yaml
# on the loki-operator Deployment
env:
  - name: RELATED_IMAGE_LOKI
    value: registry.internal/grafana/loki:3.x
  - name: RELATED_IMAGE_GATEWAY
    value: registry.internal/observatorium/api:latest
```

— and every component the operator creates pulls from there. This is the one
workload whose images are mirrored at operator install rather than through
`kurly.mirror`, because the images are the operator's to choose.

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-loki, namespace: logging }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/loki
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-loki, namespace: logging }
spec: { sourceRef: { kind: OCIRepository, name: kurly-loki } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: loki, namespace: logging }
spec:
  serviceAccountName: loki-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local loki = import 'github.com/metio/kurly/workloads/loki/server.libsonnet';
      function(size='1x.small')
        kurly.list(loki(size=size, storageSecret='loki-s3'))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,      importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-loki, importPath: github.com/metio/kurly/workloads/loki }
  tlas:
    - name: size
      value: 1x.small
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: loki, namespace: logging }
spec:
  serviceAccountName: loki-deployer
  stages:
    - name: loki
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: loki
      readyChecks:
        checks:
          - apiVersion: loki.grafana.com/v1
            kind: LokiStack
            name: loki
```
