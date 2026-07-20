// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// filebrowser — a File Browser server (a self-hosted web file manager: browse, upload,
// edit and share files from a directory through a clean UI). A plain composable
// kurly.http workload on the official image; its SQLite database lives on a
// PersistentVolume. Import it, adapt with the parameters below, and render with
// kurly.list:
//
//   local filebrowser = import 'github.com/metio/kurly/workloads/filebrowser/server.libsonnet';
//   kurly.list(filebrowser())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// FILES: File Browser manages the directory mounted at /srv. Compose the volume you want
// to serve onto that path (a PersistentVolume, or an existing data volume); the config
// volume below holds only the app's own database.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='filebrowser',
  image='docker.io/filebrowser/filebrowser:v2.63.18',
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env({ FB_DATABASE: '/database/filebrowser.db', FB_ROOT: '/srv' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/database', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
