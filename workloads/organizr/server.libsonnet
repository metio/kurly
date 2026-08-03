// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// organizr — an Organizr server (a self-hosted HTPC/homelab services dashboard that ties your
// apps together behind one tabbed interface with authentication). A plain composable kurly.http
// workload on the official image; its SQLite config lives on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local organizr = import 'github.com/metio/kurly/workloads/organizr/server.libsonnet';
//   kurly.list(organizr())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// The image publishes only a rolling tag, so it is pinned by digest here; Renovate resolves and
// updates the digest. The Apache master runs as root then serves as www-data.
//
// Single writer: the config lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='organizr',
  image=defaultImage,
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(env)
  + kurly.rootUser()
  // Its s6 init hands the config tree to the app user and prepares nginx's state.
  + kurly.allowPrivilegeEscalation()
  // Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'FSETID', 'KILL', 'SETGID', 'SETUID', 'SETPCAP'])
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
