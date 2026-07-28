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
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='nocobase',
  image=defaultImage,
  // The PostgreSQL it stores everything in; the password comes from the Secret.
  dbHost='nocobase-db-rw',
  dbPort=5432,
  dbName='nocobase',
  dbUser='nocobase',
  storageSize='10Gi',
  storageClass=null,
  secretName='nocobase',
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
  + kurly.env({
    DB_DIALECT: 'postgres',
    DB_HOST: dbHost,
    DB_PORT: std.toString(dbPort),
    DB_DATABASE: dbName,
    DB_USER: dbUser,
  } + env)
  // The image runs the app as root and owns its tree as root.
  + kurly.rootUser()
  // The bundled nginx writes its logs and cache in directories the image owns.
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/app/nocobase/storage', storageSize, storageClass=storageClass)
  // The bundled nginx answers only once the app behind it has installed itself,
  // which takes minutes on an empty database.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 15, failureThreshold: 40 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
