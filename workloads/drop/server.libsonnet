// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// drop — a Drop server (a distribution platform for DRM-free games: an imported
// library, a store front for the people you share it with, and a desktop client
// that installs and updates from it). A composable kurly.http workload backed by
// an EXTERNAL PostgreSQL — the cnpg-cluster workload provides one — with the game
// library and the object store on PersistentVolumes. Import it and render with
// kurly.list:
//
//   local drop = import 'github.com/metio/kurly/workloads/drop/server.libsonnet';
//   kurly.list(drop(externalUrl='https://games.example.com'))
//
// Serves on :3000 — nginx in the image fronts the Nuxt server on :4000 and the
// torrential depot on :5000, so :3000 is the only port worth exposing. Compose an
// exposure onto it.
//
// EXTERNAL_URL is what the desktop client is handed to talk back to; behind an
// exposure it must be the public URL, not the in-cluster one, or clients enrol
// against an address they cannot reach.
//
// BACKENDS & SECRETS: Drop reads DATABASE_URL from the environment. kurly authors
// no Secret; provide one holding it, pulled in via envFrom. The default pairs with
// a cnpg-cluster named drop-db.
//
// Single writer: the library and the object store are ReadWriteOnce volumes, so one
// replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='drop',
  image=defaultImage,
  // The imported games.
  librarySize='100Gi',
  // The default file-system backend's objects (artwork, metadata, uploads).
  dataSize='10Gi',
  storageClass=null,
  // The public URL the desktop client is given.
  externalUrl=null,
  // The Secret holding DATABASE_URL (kurly mints none), via envFrom.
  secretName='drop',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env((if externalUrl == null then {} else { EXTERNAL_URL: externalUrl }) + env)
  // A Service named after the workload makes Kubernetes inject DROP_PORT as a
  // tcp:// URL; the image already sets PORT itself, and nothing here wants a
  // second opinion on it.
  + kurly.disableServiceLinks()
  // nginx binds :3000 and forks its workers to another account, which it can only
  // do from root.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // nginx keeps its pid, access log and temporary bodies in the working directory
  // inside the image's own tree, and prisma writes its engines there too.
  + kurly.writableRootFilesystem()
  + kurly.store('/library', librarySize, storageClass=storageClass)
  + kurly.store('/data', dataSize, storageClass=storageClass)
  // The first start runs the Prisma migrations before anything listens.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
