// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// lubelogger — a LubeLogger server (vehicle maintenance records: services, fuel
// stops, repairs and reminders, per vehicle, with receipts attached). A plain
// composable kurly.http workload keeping its LiteDB database and uploaded
// documents on a PersistentVolume. Import it and render with kurly.list:
//
//   local lubelogger = import 'github.com/metio/kurly/workloads/lubelogger/server.libsonnet';
//   kurly.list(lubelogger())
//
// Serves the web UI on :8080 — compose an exposure onto it.
//
// Single writer: one LiteDB file on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='lubelogger',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    {
      // ASP.NET writes its DataProtection keys under $HOME, and those keys decrypt
      // the auth cookies and anything else it protected. Upstream's compose mounts
      // /root/.aspnet/DataProtection-Keys as a second volume for exactly this
      // reason; pointing HOME at the data volume puts them on the volume already
      // present instead, and keeps the path from depending on which uid runs.
      //
      // Without it the keys are regenerated on every start, which does not fail —
      // it just logs everybody out and makes previously protected values
      // unreadable.
      HOME: '/App/data',
    } + env
  )
  // The image never selects an account and needs nothing root provides.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/App/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/App/log')
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/Login', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/Login', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
