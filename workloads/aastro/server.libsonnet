// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// aastro — an Aastro API gateway (it sits in front of a set of services, matches
// an incoming request against a flow, fans it out to the upstreams that flow
// names and aggregates their answers into one response). A plain composable
// kurly.http workload on the official image; its config.yaml is the only state it
// needs, rendered as a ConfigMap. Import it and render with kurly.list:
//
//   local aastro = import 'github.com/metio/kurly/workloads/aastro/server.libsonnet';
//   kurly.list(aastro(flows=[…]))
//
// Serves proxied traffic on :7805 — compose an exposure onto it.
//
// TWO LISTENERS, and only one of them is for callers: the data port carries the
// flows, while the ADMIN port (:7806) answers the health probes, the Prometheus
// metrics and the diagnostics. Aastro binds the admin listener to 127.0.0.1 by
// default, where a kubelet probe cannot reach it and the pod never turns ready,
// so `adminBindAddr` is written explicitly; keep the admin port off any exposure
// unless the diagnostics are meant to be public.
//
// PROBES read /__health and /__ready on the ADMIN port, never the data port: a
// request to :7805 is answered by whatever upstream a flow names, so its status
// says nothing about the gateway.
//
// Stateless: routing is entirely in the configuration and nothing is kept between
// requests, so no PersistentVolume and any replica count is safe.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='aastro',
  image=defaultImage,
  replicas=2,
  // The routing flows, passed through VERBATIM into gateway.routing.flows —
  // kurly does not model Aastro's flow schema (it would drift against the
  // gateway's own reference). Empty means a gateway that answers its probes and
  // routes nothing, which is the honest default: which services to fan a request
  // out to is not something a recipe can guess.
  flows=[],
  // Read/write and header timeouts on the data listener.
  timeout='10s',
  headerTimeout='5s',
  // The admin listener must answer the kubelet, which never arrives on loopback.
  adminBindAddr='0.0.0.0',
  // The rest of gateway.* — observability, routing.rate_limiter,
  // routing.trusted_proxies, server.tls — merged over what is written here.
  gateway={},
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(7805)
  + kurly.servicePort(7805)
  + kurly.extraPort('admin', 7806)
  + kurly.env({ AASTRO_CONFIG: '/etc/aastro/config.yaml' } + env)
  // The image already runs as a fixed numeric uid and the gateway is a single Go
  // binary reading one file, so nothing about the hardened default has to give.
  + kurly.runAs(1000, gid=1000)
  + kurly.config({
    'config.yaml': std.manifestYamlDoc({
      schema: 'v1',
      gateway: {
        server: {
          port: 7805,
          timeout: timeout,
          header_timeout: headerTimeout,
        },
        admin: {
          port: 7806,
          bind_addr: adminBindAddr,
        },
        routing: {
          flows: flows,
        },
      } + gateway,
    }, quote_keys=false),
  }, mountPath='/etc/aastro')
  + kurly.readinessProbe({ httpGet: { path: '/__ready', port: 'admin' } })
  + kurly.livenessProbe({ httpGet: { path: '/__health', port: 'admin' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
