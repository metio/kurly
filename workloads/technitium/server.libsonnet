// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// technitium — a Technitium DNS Server (a self-hosted, privacy-focused authoritative and
// recursive DNS server with ad-blocking, DNS-over-HTTPS/TLS and a full web console). A plain
// composable kurly.http workload on the official image; its configuration and zones live on a
// PersistentVolume. Import it, point it at its admin secret, and render with kurly.list:
//
//   local technitium = import 'github.com/metio/kurly/workloads/technitium/server.libsonnet';
//   kurly.list(technitium())
//
// Serves the web console on :5380 — compose an exposure onto it.
//
// DNS: Technitium answers DNS on :53 (TCP and UDP), published on the Service beside the web
// port (the 'dns-tcp' and 'dns-udp' ports); route it (usually a LoadBalancer) so clients can
// point their resolver at it. The console works without it.
//
// SECRET: set the admin password through DNS_SERVER_ADMIN_PASSWORD from a Secret via
// kurly.envFromSecret; kurly authors no Secret. It binds the privileged DNS port, so it runs
// as root with a writable root filesystem.
//
// Single writer: the config and zones live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='technitium',
  image='docker.io/technitium/dns-server:13.2.0',
  storageSize='2Gi',
  storageClass=null,
  secretName='technitium-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5380)
  + kurly.servicePort(5380)
  + kurly.extraPort('dns-tcp', 53)
  + kurly.extraPort('dns-udp', 53, protocol='UDP')
  + kurly.envFromSecret(secretName)
  + kurly.env({ DNS_SERVER_WEB_SERVICE_HTTP_PORT: '5380' } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/etc/dns', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
