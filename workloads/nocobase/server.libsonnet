// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// nocobase — a NocoBase server (a self-hosted, open-source no-code/low-code platform for
// building internal tools, databases and workflows). A plain composable kurly.http workload on
// the official image, backed by an external PostgreSQL, with its storage on a PersistentVolume.
// Import it, point it at a database, and render with kurly.list:
//
//   local nocobase = import 'github.com/metio/kurly/workloads/nocobase/server.libsonnet';
//   kurly.list(nocobase())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: NocoBase reads its PostgreSQL connection (DB_DIALECT=postgres plus DB_*)
// and APP_KEY from the environment. kurly authors no Secret; provide one holding them, via
// envFrom. Pairs with a cnpg-cluster named nocobase-db.
//
// Single writer: the storage lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='nocobase',
  image='docker.io/nocobase/nocobase:1.4.0',
  storageSize='10Gi',
  storageClass=null,
  secretName='nocobase-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env({ DB_DIALECT: 'postgres' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/nocobase/storage', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
