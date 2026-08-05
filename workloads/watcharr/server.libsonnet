// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// watcharr — a Watcharr server (a watchlist for films and television: track what
// you have seen, what you are part-way through and what you mean to watch, with
// ratings and progress). A plain composable kurly.http workload keeping its SQLite
// database on a PersistentVolume. Import it and render with kurly.list:
//
//   local watcharr = import 'github.com/metio/kurly/workloads/watcharr/server.libsonnet';
//   kurly.list(watcharr())
//
// Serves the web app and API on :3080 — compose an exposure onto it.
//
// It looks film and series metadata up from TMDB at runtime, so the pod needs
// egress to the internet even though nothing else here does. A NetworkPolicy
// composed onto it should allow that or the catalogue simply stays empty.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='watcharr',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  // The Secret holding JWT_SECRET, which signs the tokens users hold. Watcharr
  // generates one into its data directory when unset — which survives a restart
  // here, since that directory is the volume, but not a move to a fresh one.
  // Supplying it makes the sessions outlive the volume.
  secretName='watcharr',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3080)
  + kurly.servicePort(3080)
  + (if env == {} then {} else kurly.env(env))
  + kurly.envFromSecret(secretName)
  // The image never selects an account and needs nothing root provides.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
