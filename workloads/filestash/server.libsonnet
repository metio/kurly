// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// filestash — a Filestash server (a self-hosted web file manager that puts a modern UI in front
// of many storage backends: SFTP, FTP, S3, WebDAV, Git, and more). A plain composable kurly.http
// workload on the official image; its configuration lives on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local filestash = import 'github.com/metio/kurly/workloads/filestash/server.libsonnet';
//   kurly.list(filestash())
//
// Serves the web app on :8334 — compose an exposure onto it. Add your storage backends in the
// admin console; the files themselves live on those backends, not here.
//
// The image publishes only a rolling tag, so it is pinned by digest here; Renovate resolves and
// updates the digest.
//
// Single writer: the config lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='filestash',
  image='docker.io/machines/filestash:latest@sha256:1d621a2f96785c0ae711805593d1005fbf80068bd437a25a95b1462004ef57ca',
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8334)
  + kurly.servicePort(8334)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/data/state', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
