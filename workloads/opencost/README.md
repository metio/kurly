<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# opencost

[OpenCost](https://opencost.io/) — the CNCF cost-monitoring model. It reads
resource usage from **Prometheus**, joins it with on-prem/cloud pricing, and
exposes per-workload cost metrics (and an API) that Prometheus scrapes back and
Grafana charts. A plain composable `kurly.http` workload — but one that needs
**cluster** read access to attribute cost across every namespace, so it carries a
ServiceAccount + ClusterRole + ClusterRoleBinding.

It completes the observability picture alongside [prometheus](../prometheus/) /
[thanos](../thanos/) (metrics), [loki](../loki/) (logs), [tempo](../tempo/)
(traces), and [grafana](../grafana/): point it at your Prometheus and add a cost
dashboard.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local opencost = import 'github.com/metio/kurly/workloads/opencost/server.libsonnet';

kurly.list(opencost(
  namespace='opencost',
  prometheusEndpoint='http://prometheus-operated.monitoring.svc:9090',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `opencost` | |
| `namespace` | `opencost` | **must match where you deploy** — see below |
| `image` | `ghcr.io/opencost/opencost:1.119.2` | the cost model (the UI is a separate image) |
| `prometheusEndpoint` | prometheus workload's Service | the Prometheus (or Thanos Query) to read usage from |
| `replicas` | `1` | |
| `env` | `{}` | extra pricing/cloud settings (`CLOUD_PROVIDER_API_KEY`, `CLUSTER_ID`, …) |
| `resources` / `labels` / `annotations` | | |

## Why `namespace` is required

OpenCost reads **cluster-scoped** objects (nodes) and pods in **every** namespace
to attribute cost, so it needs a `ClusterRole` + `ClusterRoleBinding`, not a
namespaced Role (which is all the `http` kind mints on its own). A
`ClusterRoleBinding` names its `ServiceAccount` subject by namespace, and a
cluster-scoped object can't be namespace-stamped by the consumer later — so the
namespace has to be known at render, and it must match where you actually deploy.
(Same reason the [prometheus](../prometheus/) workload takes a `namespace`.)

## Data source and dashboards

`prometheusEndpoint` defaults to the [prometheus](../prometheus/) workload's
`prometheus-operated` Service; point it at a [Thanos Query](../thanos/) instead
for the global, long-retention view. OpenCost serves its own metrics on `:9003` —
scrape them back into Prometheus (a `kurly.serviceMonitor`, or the operator's
`ServiceMonitor`) and add the OpenCost Grafana dashboards.

The web **UI** is a separate image (`ghcr.io/opencost/opencost-ui`); this workload
is the cost model. Run the UI as its own `kurly.http` if you want the built-in
dashboard rather than Grafana.

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
metadata: { name: kurly, namespace: opencost }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-opencost, namespace: opencost }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/opencost, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: opencost }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-opencost, namespace: opencost }
spec: { sourceRef: { kind: OCIRepository, name: kurly-opencost } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: opencost, namespace: opencost }
spec:
  serviceAccountName: opencost-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/opencost/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-opencost, importPath: github.com/metio/kurly/workloads/opencost }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: opencost, namespace: opencost }
spec:
  serviceAccountName: opencost-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: opencost
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: opencost }
```

<!-- END generated: jaas-deploy -->
