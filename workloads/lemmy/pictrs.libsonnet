// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// lemmy (pictrs) — the pict-rs image server Lemmy uses to store and process uploaded images and
// thumbnails. A plain composable kurly.http workload on the official image; its images live on a
// PersistentVolume. Import it, point it at its API key, and render with kurly.list:
//
//   local pictrs = import 'github.com/metio/kurly/workloads/lemmy/pictrs.libsonnet';
//   kurly.list(pictrs())
//
// Serves the API on :8080 — the Lemmy backend reaches it at http://pictrs:8080.
//
// SECRET: pict-rs authenticates the backend with an API key (PICTRS__SERVER__API_KEY), the same
// value the backend's config references. kurly authors no Secret; provide one holding it, via
// envFrom.
//
// Single writer: the images live on a ReadWriteOnce volume, so one replica, recreated (point its
// object storage at S3 to scale out).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='pictrs',
  image='docker.io/asonix/pictrs:0.5.16',
  storageSize='20Gi',
  storageClass=null,
  secretName='pictrs-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env({ PICTRS__SERVER__ADDRESS: '0.0.0.0:8080', PICTRS__REPO__TYPE: 'sled', PICTRS__STORE__TYPE: 'filesystem' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/mnt', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
