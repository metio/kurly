// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// damselfly — a Damselfly server (a server-based photo management app that indexes a
// folder of pictures and finds people and objects in them with local ML models). A plain
// composable kurly.http workload on the official image, keeping its SQLite database and
// generated thumbnails on PersistentVolumes alongside the picture library it scans.
// Import it and render with kurly.list:
//
//   local damselfly = import 'github.com/metio/kurly/workloads/damselfly/server.libsonnet';
//   kurly.list(damselfly())
//
// Serves the web app on :6363 — compose an exposure onto it.
//
// STORAGE: the entrypoint runs the server against three fixed paths — /pictures (the
// library it indexes), /config (its SQLite database, logs and settings) and /thumbs (the
// generated thumbnail cache) — so this composes kurly.store three times, one PVC each.
// Size pictureSize to the library you intend to keep there.
//
// The image declares no USER and the server writes into its own install tree at /app
// (fonts it installs, the ML models it unpacks), so this runs as root with a writable
// root filesystem; capabilities stay dropped and privilege escalation stays refused.
//
// Indexing and face/object recognition run in-process on start, so the first boot is slow
// and CPU-hungry on a large library: the startup probe carries the wait, not a stretched
// liveness delay.
//
// Single writer: one SQLite database on ReadWriteOnce volumes, so one replica, recreated
// (never rolled) to keep two pods off the same files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='damselfly',
  image=defaultImage,
  // The picture library Damselfly indexes, its database/config, and the thumbnail cache.
  pictureSize='100Gi',
  configSize='10Gi',
  thumbsSize='20Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6363)
  + kurly.servicePort(6363)
  + kurly.env(env)
  // The image declares no USER and the server writes into its own install tree at
  // /app (fonts, the ML models it unpacks), so it runs as root with a writable root
  // filesystem; capabilities stay dropped and privilege escalation stays refused.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // Three distinct PVCs, one per path the entrypoint passes to the server.
  + kurly.store('/pictures', pictureSize, storageClass=storageClass)
  + kurly.store('/config', configSize, storageClass=storageClass)
  + kurly.store('/thumbs', thumbsSize, storageClass=storageClass)
  // First start indexes the library before it serves: the startup probe carries the wait.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' }, periodSeconds: 15 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
