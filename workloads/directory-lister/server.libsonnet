// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// directory-lister — a Directory Lister server (a PHP web index that browses and serves
// the contents of a folder: search, sort, README rendering and zip downloads). A plain
// composable kurly.http workload on the official image, with the listed folder on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local directoryLister = import 'github.com/metio/kurly/workloads/directory-lister/server.libsonnet';
//   kurly.list(directoryLister())
//
// Serves the index on :80 — compose an exposure onto it.
//
// FILES: the image reads FILES_PATH (/data) and lists whatever is there. The volume
// mounted at that path is the content — fill it from wherever the files come from
// (a sidecar sync, an rsync job, a ReadWriteMany claim another workload writes).
//
// Single writer: the content lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='directory-lister',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  filesPath='/data',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env({ FILES_PATH: filesPath } + env)
  // The image declares root, but it runs as an ordinary uid: its files are
  // world-readable and everything it writes is under a volume fsGroup owns.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Writes under /var/run/apache2; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/run/apache2')
  // The file cache driver and the view cache both write beside the application code,
  // under /var/www/html/app/cache; a scratch there keeps the rest of the root
  // filesystem read-only.
  + kurly.scratch('/var/www/html/app/cache')
  + kurly.store(filesPath, storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
