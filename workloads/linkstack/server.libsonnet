// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// linkstack — a LinkStack server (a self-hosted, customizable "link in bio" page — a private
// alternative to Linktree). A plain composable kurly.http workload on the official image; with
// the default SQLite backend its data lives on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local linkstack = import 'github.com/metio/kurly/workloads/linkstack/server.libsonnet';
//   kurly.list(linkstack())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// The image publishes only a rolling tag, so it is pinned by digest here; Renovate resolves and
// updates the digest. The Apache master runs as root then serves as www-data.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='linkstack',
  image='ghcr.io/linkstackorg/linkstack:latest@sha256:6e7e8f44099f7c4f1340bb9ffda5411f97da766a06fd63cf1ff90c57ce22dd61',
  storageSize='2Gi',
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
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/htdocs', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
