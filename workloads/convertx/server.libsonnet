// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// convertx — a ConvertX server (a self-hosted online file converter supporting 1000+
// formats: images, documents, audio, video and more). A plain composable kurly.http
// workload on the official image; its SQLite database and in-flight files live on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local convertx = import 'github.com/metio/kurly/workloads/convertx/server.libsonnet';
//   kurly.list(convertx())
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// SECRET: set JWT_SECRET (session signing) from a Secret via kurly.envFromSecret; kurly
// authors no Secret. Set ACCOUNT_REGISTRATION=false after creating your account.
//
// Single writer: the database and files live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='convertx',
  image='ghcr.io/c4illin/convertx:v0.18.0',
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
