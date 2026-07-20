// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// photoview — a Photoview server (a self-hosted photo gallery for photographers: it scans a
// media library, builds albums and serves them with face recognition and RAW support). A plain
// composable kurly.http workload on the official image, backed by an external MySQL/MariaDB or
// PostgreSQL, with TWO PersistentVolumes — the media library it scans and a thumbnail cache.
// Import it, point it at a database, and render with kurly.list:
//
//   local photoview = import 'github.com/metio/kurly/workloads/photoview/server.libsonnet';
//   kurly.list(photoview())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// STORAGE: Photoview keeps two directories on disk — the media library at /photos (add photos
// there for it to scan) and the generated cache at /app/cache — so this composes kurly.store
// twice, one PVC each. Point mediaSize at your library's size.
//
// DATABASE & SECRETS: Photoview reads its database driver and connection (PHOTOVIEW_DATABASE_DRIVER
// and PHOTOVIEW_MYSQL_URL / PHOTOVIEW_POSTGRES_URL) from the environment. kurly authors no
// Secret; provide one holding them, via envFrom. Pairs with a mysql-cluster named photoview-db.
//
// Single writer: the media and cache live on ReadWriteOnce volumes, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='photoview',
  image='docker.io/viktorstrate/photoview:2.4.0',
  mediaSize='100Gi',
  cacheSize='20Gi',
  storageClass=null,
  secretName='photoview-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '256Mi' }, limits: { memory: '1Gi' } },
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
  + kurly.env({ PHOTOVIEW_LISTEN_IP: '0.0.0.0', PHOTOVIEW_LISTEN_PORT: '80', PHOTOVIEW_MEDIA_CACHE: '/app/cache' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  // Two distinct PVCs: the media library it scans, and the thumbnail cache.
  + kurly.store('/photos', mediaSize, storageClass=storageClass)
  + kurly.store('/app/cache', cacheSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
