// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// podfetch — a Podfetch server (a self-hosted podcast manager: it subscribes to
// feeds, downloads the episodes, and plays them in the browser, with a GPodder
// endpoint so an existing podcast app keeps syncing against it). A plain
// composable kurly.http workload backed by SQLite — no external database. Import
// it and render with kurly.list:
//
//   local podfetch = import 'github.com/metio/kurly/workloads/podfetch/server.libsonnet';
//   kurly.list(podfetch())
//
// Serves the web app on :8000 — compose an exposure onto it.
//
// TWO volumes, because the two things it keeps grow at completely different
// rates: the SQLite database at /app/db, and the downloaded audio at
// /app/podcasts, which is the one that fills a disk.
//
// Single writer: SQLite on a ReadWriteOnce volume, so one replica, recreated
// (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='podfetch',
  image=defaultImage,
  // The downloaded episodes — audio files, so size this for the library you
  // intend to keep, not for the metadata.
  storageSize='50Gi',
  // The SQLite database and its migrations.
  databaseSize='1Gi',
  storageClass=null,
  // How often, in MINUTES, the feeds are polled for new episodes — the unit the
  // server prints back on start, not the seconds the name suggests.
  pollingInterval=60,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(
    {
      DATABASE_URL: 'sqlite:///app/db/podcast.db',
      POLLING_INTERVAL: std.toString(pollingInterval),
    } + env
  )
  // The image declares no user and the binary is static, so it runs happily as
  // an unprivileged uid — pinned here with a matching fsGroup so both volumes
  // are writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/db', databaseSize, storageClass=storageClass)
  + kurly.store('/app/podcasts', storageSize, storageClass=storageClass)
  // ffmpeg/ffprobe stage their work in a temporary directory, and the root
  // filesystem stays read-only.
  + kurly.scratch('/tmp', '1Gi')
  // A Service named after the workload makes Kubernetes inject PODFETCH_PORT as
  // a tcp:// URL, and the server reads its own PORT-shaped variables.
  + kurly.disableServiceLinks()
  // The database migrations run before the listener comes up on a fresh volume.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
