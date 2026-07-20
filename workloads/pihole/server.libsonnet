// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pihole — a Pi-hole server (a self-hosted, network-wide DNS sinkhole that blocks ads and
// trackers for every device on your network, with a web admin dashboard). A plain
// composable kurly.http workload on the official image; its configuration and query
// database live on a PersistentVolume. Import it, point it at its admin secret, and render
// with kurly.list:
//
//   local pihole = import 'github.com/metio/kurly/workloads/pihole/server.libsonnet';
//   kurly.list(pihole())
//
// Serves the admin dashboard on :80 — compose an exposure onto it.
//
// DNS: Pi-hole answers DNS on :53 (TCP and UDP), published on the Service beside the web port
// (the 'dns-tcp' and 'dns-udp' ports); route it (usually a LoadBalancer) so clients can point
// their resolver at it. The admin dashboard works without it.
//
// SECRET: set the admin password through FTLCONF_webserver_api_password from a Secret via
// kurly.envFromSecret; kurly authors no Secret. Pi-hole binds the privileged DNS port, so it
// runs as root with a writable root filesystem.
//
// Single writer: the config and query database live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='pihole',
  image='docker.io/pihole/pihole:2025.08.0',
  storageSize='2Gi',
  storageClass=null,
  timezone='UTC',
  secretName='pihole-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.extraPort('dns-tcp', 53)
  + kurly.extraPort('dns-udp', 53, protocol='UDP')
  + kurly.envFromSecret(secretName)
  + kurly.env({ TZ: timezone } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/etc/pihole', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/admin/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
