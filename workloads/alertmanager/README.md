<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# alertmanager

An [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/) as a
[prometheus-operator](https://github.com/prometheus-operator/prometheus-operator)
`Alertmanager` custom resource — it receives alerts from a Prometheus,
deduplicates and groups them, and routes them to receivers (email, Slack,
PagerDuty, …). Like [prometheus](../prometheus/), this authors the CR directly;
the operator reconciles it into a StatefulSet, pods, and the
`alertmanager-operated` Service.

**Prerequisite:** the prometheus-operator (its CRDs and controller) must be
installed — the same operator the prometheus workload needs.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local alertmanager = import 'github.com/metio/kurly/workloads/alertmanager/server.libsonnet';

kurly.list(alertmanager(replicas=3))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `alertmanager` | |
| `image` | `docker.io/prom/alertmanager:v0.33.1` | |
| `replicas` | `1` | 3 for a gossip-clustered, HA Alertmanager |
| `retention` | `120h` | how long notification/silence state is kept |
| `storageSize` / `storageClass` | `1Gi` / cluster default | small — silences and state |
| `resources` | `50m` / `128Mi` | request/limit |
| `alertmanagerConfigSelector` | `{}` | which configs supply routing — see below |
| `namespaceSelector` | `{}` | which namespaces they may live in |
| `spec` | `{}` | extra `Alertmanager` spec fields, merged verbatim |

## Routing

Alertmanager's routing tree and receivers come from `AlertmanagerConfig` objects,
selected by `alertmanagerConfigSelector` and `namespaceSelector`. The defaults are
`{}` — select every config in every namespace — so any `AlertmanagerConfig` in the
cluster is honoured; scope them with a label selector, or leave no config at all
and the operator runs a null default that receives alerts and drops them.

## Wiring a Prometheus to it

Alertmanager receives; Prometheus sends. Point a kurly [prometheus](../prometheus/)
at this one through that workload's `spec` escape:

```jsonnet
prometheus(
  namespace='monitoring',
  spec={
    alerting: {
      alertmanagers: [
        { namespace: 'monitoring', name: 'alertmanager-operated', port: 'web' },
      ],
    },
  },
)
```

`alertmanager-operated` is the headless Service the operator creates; Prometheus
then delivers firing alerts to it on port `web` (9093).

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-alertmanager, namespace: monitoring }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/alertmanager
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-alertmanager, namespace: monitoring }
spec: { sourceRef: { kind: OCIRepository, name: kurly-alertmanager } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: alertmanager, namespace: monitoring }
spec:
  serviceAccountName: alertmanager-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local alertmanager = import 'github.com/metio/kurly/workloads/alertmanager/server.libsonnet';
      function()
        kurly.list(alertmanager())
  libraries:
    - { kind: JsonnetLibrary, name: kurly,              importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-alertmanager, importPath: github.com/metio/kurly/workloads/alertmanager }
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: alertmanager, namespace: monitoring }
spec:
  serviceAccountName: alertmanager-deployer
  stages:
    - name: alertmanager
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: alertmanager
      readyChecks:
        checks:
          - apiVersion: monitoring.coreos.com/v1
            kind: Alertmanager
            name: alertmanager
```
