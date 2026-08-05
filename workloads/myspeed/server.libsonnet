// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// myspeed — a MySpeed server (runs speed tests on a schedule and charts the
// history, with a dashboard showing when a connection degraded). A plain
// composable kurly.http workload keeping its database on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local myspeed = import 'github.com/metio/kurly/workloads/myspeed/server.libsonnet';
//   kurly.list(myspeed())
//
// Serves the dashboard on :5216 — compose an exposure onto it.
//
// WHAT IT MEASURES FROM A CLUSTER is the node's path to the internet, not a home
// connection — the same caveat as speedtest-tracker, and the reason to think about
// where this runs before reading its graphs.
//
// Single writer: one database on a ReadWriteOnce volume, so one replica, recreated
// (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='myspeed',
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
  + kurly.port(5216)
  + kurly.servicePort(5216)
  + (if env == {} then {} else kurly.env(env))
  // The image never selects an account and needs nothing root provides.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/myspeed/data', storageSize, storageClass=storageClass)
  // It creates `data`, `bin`, `data/logs` and `data/servers` RELATIVE to its
  // working directory on every start, so /myspeed/bin — where it downloads the
  // speedtest CLI at runtime — has to be writable as well as the volume. Without
  // it the only message is "Could not create the data folder. Please check the
  // permission", which names the one directory that was fine.
  + kurly.scratch('/myspeed/bin')
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
