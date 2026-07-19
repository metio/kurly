<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# thanos-ruler

A [Thanos](https://thanos.io/) Ruler as a prometheus-operator `ThanosRuler`
custom resource. It loads recording and alerting rules from `PrometheusRule`
objects, evaluates them against **Thanos Query** — the global view across every
Prometheus, not a single one — and sends firing alerts to Alertmanager. Like
[alertmanager](../alertmanager/) and [prometheus](../prometheus/), this authors
the CR directly; the operator reconciles it into a StatefulSet, pods, and the
`thanos-ruler-operated` governing Service.

**Prerequisite:** the [prometheus-operator](https://prometheus-operator.dev/)
(its CRDs and controller) must be installed — the same operator prometheus and
alertmanager need.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ruler = import 'github.com/metio/kurly/workloads/thanos-ruler/server.libsonnet';

kurly.list(ruler(
  queryEndpoints=['dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local'],
  alertmanagersUrl=['http://alertmanager-operated.monitoring.svc:9093'],
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `thanos-ruler` | |
| `image` | `quay.io/thanos/thanos:v0.42.2` | |
| `replicas` | `1` | |
| `queryEndpoints` | `[]` | Thanos Query endpoints to evaluate rules against |
| `alertmanagersUrl` | `[]` | plain Alertmanager targets — see below |
| `ruleSelector` / `ruleNamespaceSelector` | `{}` | which `PrometheusRule` objects to load |
| `storageSize` / `storageClass` | `5Gi` / cluster default | the rule-evaluation WAL/TSDB |
| `resources` | `250m` / `512Mi` | |
| `labels` / `annotations` | `{}` | on the CR and the pods |
| `spec` | `{}` | extra `ThanosRuler` spec fields, merged verbatim |

## The rules it evaluates

The ruler loads ordinary `PrometheusRule` objects — author those separately (the
same ones a Prometheus would use). `ruleSelector` and `ruleNamespaceSelector` pass
through to the operator verbatim: `{}` selects **every** `PrometheusRule` in every
namespace, an absent selector selects **none**, so they are never pruned. Narrow
them to scope which rules this ruler owns:

```jsonnet
ruler(ruleSelector={ matchLabels: { role: 'global-alerts' } })
```

## Query endpoints

Evaluating against Thanos Query — rather than a single Prometheus — is the whole
point: the rules see the deduplicated global view. List the Query endpoints; the
`dnssrv+` prefix makes the operator resolve the SRV record so every Query replica
is used:

```jsonnet
queryEndpoints=['dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local']
```

## Sending alerts to Alertmanager

For plain, unauthenticated Alertmanagers, list their URLs:

```jsonnet
alertmanagersUrl=['http://alertmanager-operated.monitoring.svc:9093']
```

For an **authenticated** or TLS Alertmanager, the config lives in a Secret. kurly
never mints a Secret — reference one you provide through the `spec` escape, and
fill it from your secrets store with `kurly.externalSecret` (see the repository
[README](../../#secrets)):

```jsonnet
ruler(spec={
  alertmanagersConfig: { name: 'thanos-ruler-alertmanager', key: 'config.yaml' },
})
```

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-thanos-ruler, namespace: monitoring }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/thanos-ruler
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-thanos-ruler, namespace: monitoring }
spec: { sourceRef: { kind: OCIRepository, name: kurly-thanos-ruler } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: thanos-ruler, namespace: monitoring }
spec:
  serviceAccountName: thanos-ruler-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local ruler = import 'github.com/metio/kurly/workloads/thanos-ruler/server.libsonnet';
      function(queries=[])
        kurly.list(ruler(queryEndpoints=queries))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,              importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-thanos-ruler, importPath: github.com/metio/kurly/workloads/thanos-ruler }
  tlas:
    - name: queries
      value: ['dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local']
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: thanos-ruler, namespace: monitoring }
spec:
  serviceAccountName: thanos-ruler-deployer
  stages:
    - name: thanos-ruler
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: thanos-ruler
      readyChecks:
        checks:
          - apiVersion: monitoring.coreos.com/v1
            kind: ThanosRuler
            name: thanos-ruler
```
