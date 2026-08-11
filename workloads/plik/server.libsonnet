// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// plik — a temporary file upload and sharing server. A plain composable
// kurly.http workload: uploads land on a PersistentVolume and their metadata in a
// SQLite database beside them, so it needs no external database. Import it and
// render with kurly.list:
//
//   local plik = import 'github.com/metio/kurly/workloads/plik/server.libsonnet';
//   kurly.list(plik())
//
// Serves the web app and API on :8080 — compose an exposure onto it.
//
// CONFIG: plikd.cfg is rendered as a ConfigMap and mounted over the image's own
// copy. The paths it names are ABSOLUTE, because plik resolves the defaults
// (`files`, `plik.db`) relative to its working directory, which is inside the
// read-only image — both have to be moved onto the volume for the server to
// start at all. Everything else in plik's configuration is reachable through
// `config`, which merges over the defaults.
//
// PUBLIC URL: `plikDomain` is what plik puts in the download links it hands out
// and what it checks OAuth redirects against. Left null the links follow whatever
// Host the request arrived with, which is fine behind a single ingress and wrong
// behind two.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='plik',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The public URL the server is reached at, e.g. https://plik.example.com.
  plikDomain=null,
  // Merged over the rendered plikd.cfg — any of plik's own settings.
  config={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // The image's own unprivileged uid; fsGroup so the volume it stores uploads
  // and the SQLite file on is writable by it.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.config({
    'plikd.cfg': std.manifestTomlEx({
      ListenAddress: '0.0.0.0',
      ListenPort: 8080,
      DataBackend: 'file',
      DataBackendConfig: { Directory: '/data/files' },
      MetadataBackendConfig: { Driver: 'sqlite3', ConnectionString: '/data/plik.db' },
    } + (if plikDomain != null then { PlikDomain: plikDomain } else {}) + config, '  '),
  }, mountPath='/home/plik/server', subPath=true)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
