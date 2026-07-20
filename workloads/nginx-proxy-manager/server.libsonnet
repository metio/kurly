// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// nginx-proxy-manager — an Nginx Proxy Manager server (a self-hosted reverse-proxy with a web
// UI: expose your services with SSL — including free Let's Encrypt certificates — access lists
// and custom nginx config, without editing config files). A plain composable kurly.http
// workload on the official image; its SQLite database and config live on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local npm = import 'github.com/metio/kurly/workloads/nginx-proxy-manager/server.libsonnet';
//   kurly.list(npm())
//
// Serves the admin UI on :81 — compose an exposure onto it.
//
// PROXY PORTS: the actual reverse proxy listens on :80 and :443, published on the Service
// beside the admin port (the 'proxy-http' and 'proxy-https' ports); route them (usually a
// LoadBalancer) so it can serve your proxied hosts. The admin UI works without them.
//
// It binds the privileged proxy ports, so it runs as root with a writable root filesystem.
//
// Single writer: the database and certificates live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='nginx-proxy-manager',
  image='docker.io/jc21/nginx-proxy-manager:2.12.3',
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(81)
  + kurly.servicePort(81)
  + kurly.extraPort('proxy-http', 80)
  + kurly.extraPort('proxy-https', 443)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
