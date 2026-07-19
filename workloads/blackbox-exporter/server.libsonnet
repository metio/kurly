// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// blackbox-exporter — the Prometheus blackbox_exporter: it probes endpoints from
// the OUTSIDE (HTTP, TCP, DNS, ICMP) and turns each probe into metrics Prometheus
// scrapes. It is the prober that kurly.expose.probe points a workload's Probe at,
// deployed once so every workload's outside-in check runs through it. A plain
// composable kurly.http workload (not an operator custom resource). Import it and
// render with kurly.list:
//
//   local blackbox = import 'github.com/metio/kurly/workloads/blackbox-exporter/server.libsonnet';
//   kurly.list(blackbox())
//
// It serves /probe on :9115; a prometheus-operator Probe (kurly.expose.probe)
// names it as the prober and a module, and Prometheus does the rest. The default
// modules cover the common cases — http_2xx (dual-stack) plus IPv4- and
// IPv6-pinned variants, and tcp_connect. Override `modules` for custom checks; an
// ICMP module additionally needs CAP_NET_RAW, so relax the dropped capabilities
// for it (the restricted default drops all).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='blackbox-exporter',
  image='quay.io/prometheus/blackbox-exporter:v0.28.0',
  replicas=1,
  // The prober modules, rendered as the exporter's config.yml. The default set is
  // enough for kurly.expose.probe's http_2xx and for IP-family-specific checks;
  // replace it wholesale for custom probes.
  modules={
    http_2xx: { prober: 'http', timeout: '5s' },
    http_2xx_ipv4: { prober: 'http', timeout: '5s', http: { preferred_ip_protocol: 'ip4' } },
    http_2xx_ipv6: { prober: 'http', timeout: '5s', http: { preferred_ip_protocol: 'ip6' } },
    tcp_connect: { prober: 'tcp', timeout: '5s' },
  },
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '64Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(9115)
  + kurly.servicePort(9115)
  // The image sets `USER nobody` by NAME, which the kubelet cannot verify against
  // runAsNonRoot; pin the numeric uid so the restricted posture admits it.
  + kurly.runAs(65534)
  // The config the exporter reads by default (--config.file=/etc/blackbox_exporter/config.yml).
  + kurly.config({ 'config.yml': std.manifestYamlDoc({ modules: modules }, quote_keys=false) }, mountPath='/etc/blackbox_exporter')
  + kurly.readinessProbe({ httpGet: { path: '/-/healthy', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/-/healthy', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
