// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gokapi — a Gokapi server (a self-hosted, lightweight file-sharing server with expiring links and
// a download limit, similar to the discontinued Firefox Send). A plain composable kurly.http
// workload on the official image; its database, configuration and (by default) the stored files
// live on a PersistentVolume under /app/data. Import it and render with kurly.list:
//
//   local gokapi = import 'github.com/metio/kurly/workloads/gokapi/server.libsonnet';
//   kurly.list(gokapi())
//
// Serves the web app and API on :53842 — compose an exposure onto it. Uploaded files can instead
// go to S3-compatible object storage when the AWS_* settings are provided (add them via env or a
// Secret); the database and config still use the volume.
//
// Single writer: the database and local files live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the same data directory.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='gokapi',
  image='docker.io/f0rc3/gokapi:latest@sha256:7303dc0e658b8442f00d8363937ac0ffca3b4690930801b47aac6c0631d0cbcf',
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(53842)
  + kurly.servicePort(53842)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
