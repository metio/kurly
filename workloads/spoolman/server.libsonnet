// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// spoolman — a Spoolman server (keeps track of 3D-printing filament: which spools
// you own, what is left on each, and what got used by which print). A plain
// composable kurly.http workload: with the default SQLite backend its database
// lives on a PersistentVolume, so it needs nothing external. Import it and render
// with kurly.list:
//
//   local spoolman = import 'github.com/metio/kurly/workloads/spoolman/server.libsonnet';
//   kurly.list(spoolman())
//
// Serves the web UI and its REST API on :8000 — compose an exposure onto it.
//
// It has no authentication of its own; printers talk to the API with no
// credential, which is what makes the integration simple and what makes exposing
// it a decision. Keep it on the network your printers are on, or authenticate in
// front of it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='spoolman',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
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
      // Where the SQLite database goes. Named rather than left at the image's
      // default, which is a path under the app account's home directory — a
      // sensible place for a desktop install and an awkward one to mount a volume
      // over.
      SPOOLMAN_DIR_DATA: '/data',
    } + env
  )
  // The image runs as root and needs nothing root provides.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/api/v1/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/v1/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
