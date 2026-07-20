<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# otel-collector

An [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) as a
**per-node agent** — the `kurly.daemon` shape, a DaemonSet running one collector
on every node so local workloads send telemetry (traces, metrics, logs) to a
collector on their own node, which processes and forwards it onward.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local agent = import 'github.com/metio/kurly/workloads/otel-collector/agent.libsonnet';

kurly.list(agent())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `otel-collector` | |
| `image` | `docker.io/otel/opentelemetry-collector-contrib:0.156.0` | the contrib distribution (all receivers/exporters) |
| `config` | a working OTLP agent | the collector config, **verbatim** — see below |

The default receives OTLP on `4317` (gRPC) and `4318` (HTTP), guards memory,
batches, and exports to the debug logger — it runs and is healthy out of the box.
The `health_check` extension on `13133` backs the readiness and liveness probes.

## The config is yours, passed verbatim

The collector's config — `receivers`, `processors`, `exporters`, and the
`service.pipelines` wiring them together — is the whole workload, and it is the
collector's own schema, not kurly's. kurly renders whatever you pass straight
into the mounted config file; it does not model or validate the schema (a
second-hand copy would drift against the collector's). Pass your own to replace
the default:

```jsonnet
agent(config={
  receivers: { otlp: { protocols: { grpc: { endpoint: '0.0.0.0:4317' } } } },
  processors: { batch: {} },
  exporters: { otlp: { endpoint: 'gateway-collector:4317', tls: { insecure: true } } },
  service: {
    pipelines: {
      traces: { receivers: ['otlp'], processors: ['batch'], exporters: ['otlp'] },
    },
  },
})
```

If your config drops the `health_check` extension, move the probes too
(`kurly.readinessProbe` / `kurly.livenessProbe`), since they target `13133`.

## Collecting node logs (an opt-in)

The default agent only receives what workloads send it — it takes no host access,
so it stays fully `restricted`. To have each node's agent read that node's pod
logs, add a `filelog` receiver **and** mount the host log directory, which the
composable app leaves to you because it needs a hostPath volume:

```jsonnet
agent(config=logsConfig)   // a config with a filelog receiver on /var/log/pods
+ {
  daemonset+: { spec+: { template+: { spec+: {
    volumes+: [{ name: 'varlogpods', hostPath: { path: '/var/log/pods' } }],
    containers: [c { volumeMounts+: [{ name: 'varlogpods', mountPath: '/var/log/pods', readOnly: true }] } for c in super.containers],
  } } } },
}
```

A hostPath volume is **not** permitted under the Pod Security Standards
`restricted` profile, so this runs only in a namespace that admits `baseline`
(or higher). That is the deliberate trade: the powerful per-node collection needs
host access, so it is never the default.

## Reaching the agent

A DaemonSet has no Service. A workload sends OTLP to the collector on its own
node by resolving the node's IP through the downward API
(`status.hostIP`) — set, for example, `OTEL_EXPORTER_OTLP_ENDPOINT` from it —
which requires the collector to listen on a `hostPort`. Add the hostPort to the
container the same way as the log mount above, in the namespaces that allow it.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: otel-collector }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-otel-collector, namespace: otel-collector }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/otel-collector, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: otel-collector }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-otel-collector, namespace: otel-collector }
spec: { sourceRef: { kind: OCIRepository, name: kurly-otel-collector } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: otel-collector, namespace: otel-collector }
spec:
  serviceAccountName: otel-collector-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local agent = import 'github.com/metio/kurly/workloads/otel-collector/agent.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(agent())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-otel-collector, importPath: github.com/metio/kurly/workloads/otel-collector }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: otel-collector, namespace: otel-collector }
spec:
  serviceAccountName: otel-collector-deployer
  rollbackOnFailure: true
  stages:
    - name: agent
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: otel-collector
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: DaemonSet, name: otel-collector }
```

<!-- END generated: jaas-deploy -->
