// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// blocky — a fast, lightweight DNS proxy and ad-blocker for a local network (a
// Pi-hole alternative with no database and no web console). A plain composable
// kurly.http workload on the official image; its config.yml is the only state it
// needs, rendered as a ConfigMap. Import it and render with kurly.list:
//
//   local blocky = import 'github.com/metio/kurly/workloads/blocky/server.libsonnet';
//   kurly.list(blocky())
//
// Serves its REST API and Prometheus metrics on :4000 — compose an exposure onto
// it if you want either.
//
// DNS: blocky answers DNS on :53 (TCP and UDP), published on the Service beside
// the API port (the 'dns-tcp' and 'dns-udp' ports); route it (usually a
// LoadBalancer) so clients can point their resolver at it. The API works
// without it.
//
// CONFIG: `upstreams` sets the default resolver group (blocky refuses to start
// without at least one), rendered into config.yml alongside the ports; override
// it wholesale for a different resolver set or any of blocky's other config.yml
// sections. No Secret: blocky's config carries no credential.
//
// Stateless: blocky keeps no database, so no PersistentVolume and any replica
// count is safe — its own on-disk caches (blocklist downloads, the optional
// query log) live under a scratch volume instead.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='blocky',
  image=defaultImage,
  replicas=1,
  // The default upstream resolver group; blocky needs at least one upstream in
  // its 'default' group to start at all.
  upstreams={ default: ['1.1.1.1', '8.8.8.8'] },
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(4000)
  + kurly.servicePort(4000)
  + kurly.extraPort('dns-tcp', 53)
  + kurly.extraPort('dns-udp', 53, protocol='UDP')
  // The image runs as a fixed numeric uid already, so the restricted posture
  // needs only the one privilege a DNS server holds: binding :53.
  + kurly.runAs(100, gid=100)
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  // /app/cache holds downloaded blocklists, /logs the optional query log — both
  // owned by the image's own uid and written to at runtime.
  + kurly.scratch('/app/cache')
  + kurly.scratch('/logs')
  // Mounted with subPath so only config.yml lands in /app, leaving the blocky
  // binary and the image's own /app/cache untouched.
  // `ports.http` is written EXPLICITLY rather than left to blocky's default,
  // because the default is off: without it blocky serves DNS and nothing else,
  // the probes on :4000 are refused, and the liveness probe restarts a container
  // that is answering queries perfectly well. The number here and the one
  // kurly.port declares above are the same port for that reason — a stage may
  // only declare a port its image actually binds.
  + kurly.config({
    'config.yml': std.manifestYamlDoc({
      upstreams: { groups: upstreams },
      ports: { http: 4000 },
    }, quote_keys=false),
  }, mountPath='/app', subPath=true)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
