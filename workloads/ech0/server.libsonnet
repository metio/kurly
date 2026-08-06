// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ech0 — an Ech0 server (a lightweight publishing platform for short posts, with
// federation between instances). A plain composable kurly.http workload keeping its
// SQLite database and uploaded media on a PersistentVolume. Import it and render
// with kurly.list:
//
//   local ech0 = import 'github.com/metio/kurly/workloads/ech0/server.libsonnet';
//   kurly.list(ech0())
//
// Serves the web app and API on :6277 — compose an exposure onto it.
//
// SECRET: JWT_SECRET signs the tokens users hold, and the image ships a documented
// default, so an instance left with it is one anybody can mint an admin token for.
// kurly authors no Secret; supply one and it is read via envFrom.
//
// Single writer: one SQLite database and one media directory on a ReadWriteOnce
// volume, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='ech0',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // The Secret holding JWT_SECRET (kurly mints none), pulled in via envFrom.
  secretName='ech0',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6277)
  + kurly.servicePort(6277)
  + kurly.envFromSecret(secretName)
  + (if env == {} then {} else kurly.env(env))
  // A single Go binary that selects no account and needs nothing root provides;
  // it creates its database and media directories under the volume, hence fsGroup.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
