<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# blackbox-exporter

The [Prometheus blackbox_exporter](https://github.com/prometheus/blackbox_exporter):
it probes endpoints from the **outside** (HTTP, TCP, DNS, ICMP) and turns each
probe into metrics Prometheus scrapes. Deploy it once, and it becomes the prober
that `kurly.expose.probe` points every workload's `Probe` at — the outside-in
check (does the site actually answer over the network?) that complements an
in-cluster `ServiceMonitor` scrape. A plain composable `kurly.http` workload.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local blackbox = import 'github.com/metio/kurly/workloads/blackbox-exporter/server.libsonnet';

kurly.list(blackbox())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `blackbox-exporter` | the `kurly.expose.probe` default prober is `blackbox-exporter:9115` |
| `image` | `quay.io/prometheus/blackbox-exporter:v0.28.0` | |
| `replicas` | `1` | |
| `modules` | http/tcp set — see below | rendered as the exporter's `config.yml` |
| `resources` / `labels` / `annotations` | | |

It serves `/probe` on `:9115`. The name and port match `kurly.expose.probe`'s
defaults, so an exposed workload wires up with nothing to configure:

```jsonnet
kurly.http('web', image)
+ kurly.expose.ownGateway('web.example.com', 'istio', tls='web-tls')
+ kurly.expose.probe('web.example.com')   // → blackbox-exporter:9115, module http_2xx
```

**Prerequisite:** the prometheus-operator (the `Probe` CRD and a Prometheus that
selects it).

## Modules

`modules` is rendered straight into the exporter's `config.yml`. The default set
covers the common cases — `http_2xx` (dual-stack) plus IPv4- and IPv6-pinned
variants, and `tcp_connect`:

```jsonnet
blackbox(modules={
  http_2xx: { prober: 'http', timeout: '5s' },
  http_2xx_ipv4: { prober: 'http', timeout: '5s', http: { preferred_ip_protocol: 'ip4' } },
  http_2xx_ipv6: { prober: 'http', timeout: '5s', http: { preferred_ip_protocol: 'ip6' } },
  tcp_connect: { prober: 'tcp', timeout: '5s' },
  dns_udp: { prober: 'dns', dns: { query_name: 'example.com', query_type: 'A' } },
})
```

Replace it wholesale for custom checks. An **ICMP** module additionally needs
`CAP_NET_RAW`, which the restricted default drops — relax capabilities for the
container if you probe over ICMP.

## Deploy through JaaS and stageset

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-blackbox-exporter, namespace: monitoring }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/blackbox-exporter
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-blackbox-exporter, namespace: monitoring }
spec: { sourceRef: { kind: OCIRepository, name: kurly-blackbox-exporter } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: blackbox-exporter, namespace: monitoring }
spec:
  serviceAccountName: blackbox-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local blackbox = import 'github.com/metio/kurly/workloads/blackbox-exporter/server.libsonnet';
      function() kurly.list(blackbox())
  libraries:
    - { kind: JsonnetLibrary, name: kurly,                    importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-blackbox-exporter,  importPath: github.com/metio/kurly/workloads/blackbox-exporter }
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: blackbox-exporter, namespace: monitoring }
spec:
  serviceAccountName: blackbox-deployer
  stages:
    - name: blackbox-exporter
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: blackbox-exporter
      readyChecks:
        checks:
          - apiVersion: apps/v1
            kind: Deployment
            name: blackbox-exporter
```
