<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# grafana

A [Grafana](https://grafana.com/) instance as a
[grafana-operator](https://github.com/grafana/grafana-operator) `Grafana` custom
resource, with a Prometheus `GrafanaDatasource` wired in by default. Like
[cnpg-cluster](../cnpg-cluster/) and [prometheus](../prometheus/), this authors
CRs directly — the operator reconciles them into a Deployment, Service, and
ServiceAccount, and imports the datasource into the running Grafana.

**Prerequisite:** the grafana-operator (its CRDs and controller) must be
installed in the cluster.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local grafana = import 'github.com/metio/kurly/workloads/grafana/server.libsonnet';

kurly.list(grafana(prometheusUrl='http://prometheus-operated.monitoring.svc:9090'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `grafana` | |
| `image` | `docker.io/grafana/grafana:12.4.5` | |
| `replicas` | `1` | |
| `config` | `{}` | grafana.ini overrides, merged over the defaults |
| `resources` | `100m` / `256Mi` | request/limit |
| `prometheusDatasource` | `true` | author a Prometheus datasource |
| `prometheusUrl` | `http://prometheus-operated:9090` | where it points |
| `labels` / `annotations` | `{}` | on the `Grafana` CR |
| `spec` | `{}` | extra `Grafana` spec fields, merged verbatim |

## The pairing with prometheus

This is the other half of kurly's metrics story. The default `GrafanaDatasource`
points at the [prometheus](../prometheus/) workload's `prometheus-operated`
Service, so a Grafana deployed alongside a kurly Prometheus in the same namespace
sees its metrics with no extra wiring — set `prometheusUrl` to reach one in
another namespace, or `prometheusDatasource=false` to author none. The operator
matches the datasource to this instance by its `app.kubernetes.io/name` label.

## Configuration

`config` is [grafana.ini](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/)
as the operator takes it — sections of **string-valued** keys — merged over
kurly's defaults, which silence the phone-home and update-check traffic a server
should not make:

```jsonnet
grafana(config={
  server: { root_url: 'https://grafana.example.com' },
  auth: { disable_login_form: 'true' },
})
```

Anything the operator's `Grafana` spec accepts but this workload does not surface
(`ingress`, `route`, an explicit `persistentVolumeClaim`, …) goes through `spec`,
merged verbatim.

## Logging in

The operator mints a random admin password into the Secret
`<name>-admin-credentials` (keys `GF_SECURITY_ADMIN_USER` /
`GF_SECURITY_ADMIN_PASSWORD`). Read it with:

```shell
kubectl get secret grafana-admin-credentials \
  -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 -d
```

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-grafana, namespace: monitoring }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/grafana
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-grafana, namespace: monitoring }
spec: { sourceRef: { kind: OCIRepository, name: kurly-grafana } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: grafana, namespace: monitoring }
spec:
  serviceAccountName: grafana-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local grafana = import 'github.com/metio/kurly/workloads/grafana/server.libsonnet';
      function()
        kurly.list(grafana())
  libraries:
    - { kind: JsonnetLibrary, name: kurly,         importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-grafana, importPath: github.com/metio/kurly/workloads/grafana }
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: grafana, namespace: monitoring }
spec:
  serviceAccountName: grafana-deployer
  stages:
    - name: grafana
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: grafana
      readyChecks:
        checks:
          - apiVersion: grafana.integreatly.org/v1beta1
            kind: Grafana
            name: grafana
```
