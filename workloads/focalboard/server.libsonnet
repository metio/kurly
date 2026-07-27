// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// focalboard — a Focalboard server (a self-hosted project-management and kanban tool for
// boards, tasks and roadmaps, an open alternative to Trello/Notion/Asana). A plain
// composable kurly.http workload on the official image; with the default SQLite backend its
// database and uploaded files live on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local focalboard = import 'github.com/metio/kurly/workloads/focalboard/server.libsonnet';
//   kurly.list(focalboard())
//
// Serves the web app on :8000 — compose an exposure onto it.
//
// Single writer: the SQLite database and files live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='focalboard',
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
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  // The bundled config keeps the SQLite database and uploaded files under the
  // app's own data directory, relative to its working directory.
  + kurly.store('/opt/focalboard/data', storageSize, storageClass=storageClass)
  // The app reads PORT from the environment, which the Service-link variables
  // would overwrite with a tcp:// URL.
  + kurly.disableServiceLinks()
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
