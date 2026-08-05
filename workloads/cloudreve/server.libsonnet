// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cloudreve — a Cloudreve server (self-hosted file storage and sharing with a web
// UI: upload, organise and share files, backed by local disk or by any S3-style
// object storage you point it at). A plain composable kurly.http workload: its
// SQLite database, configuration and — by default — the stored files live on one
// PersistentVolume. Import it and render with kurly.list:
//
//   local cloudreve = import 'github.com/metio/kurly/workloads/cloudreve/server.libsonnet';
//   kurly.list(cloudreve())
//
// Serves the web UI and API on :5212 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file. Point it at PostgreSQL
// and object storage from its own settings UI to move both off the volume.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='cloudreve',
  image=defaultImage,
  storageSize='20Gi',
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
  + kurly.port(5212)
  + kurly.servicePort(5212)
  + (if env == {} then {} else kurly.env(env))
  // The image runs as root and drops nothing, but needs nothing root gives it
  // either: every port it binds is above 1024 and the only path it writes is the
  // volume. Naming an unprivileged uid keeps the hardened posture, and fsGroup is
  // what makes the volume writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/cloudreve/data', storageSize, storageClass=storageClass)
  // The entrypoint starts supervisord for the bundled aria2 downloader before the
  // server, and supervisord wants somewhere for its socket and pid.
  + kurly.scratch('/tmp')
  + kurly.scratch('/var/run')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
