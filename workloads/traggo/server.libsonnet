// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// traggo — a Traggo server (tag-based time tracking: entries carry tags rather
// than living in a fixed project tree, and the dashboard is built from queries
// over them). A plain composable kurly.http workload keeping its SQLite database
// on a PersistentVolume — no external database. Import it and render with
// kurly.list:
//
//   local traggo = import 'github.com/metio/kurly/workloads/traggo/server.libsonnet';
//   kurly.list(traggo())
//
// Serves the web app and GraphQL API on :3030 — compose an exposure onto it.
//
// SECRET: the server creates its first account on an empty database from
// TRAGGO_DEFAULT_USER_NAME/TRAGGO_DEFAULT_USER_PASS, whose documented defaults are
// admin/admin, so an instance left with them is one anybody can sign in to as
// admin. kurly authors no Secret; supply one and it is read via envFrom.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='traggo',
  image=defaultImage,
  storageSize='1Gi',
  storageClass=null,
  // The Secret holding TRAGGO_DEFAULT_USER_PASS (kurly mints none), pulled in via
  // envFrom.
  secretName='traggo',
  env={},
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3030)
  + kurly.servicePort(3030)
  + kurly.env(
    {
      TRAGGO_PORT: '3030',
      // The default connection is relative to the image's working directory
      // (/opt/traggo/data/traggo.db), which the read-only root filesystem refuses;
      // point it at the volume instead.
      TRAGGO_DATABASE_DIALECT: 'sqlite3',
      TRAGGO_DATABASE_CONNECTION: '/data/traggo.db',
      TRAGGO_DEFAULT_USER_NAME: 'admin',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // A Service named traggo makes Kubernetes inject TRAGGO_PORT as a tcp:// URL —
  // the exact variable the server reads as its listen port.
  + kurly.disableServiceLinks()
  // A single static Go binary in a scratch image that selects no account and needs
  // nothing root provides; it creates its database under the volume, hence fsGroup.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
