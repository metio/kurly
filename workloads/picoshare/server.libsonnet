// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// picoshare — a PicoShare server (a minimal file-sharing app: upload a file, get a
// link, optionally with an expiry). A plain composable kurly.http workload — the
// files and their metadata all live in ONE SQLite database on a PersistentVolume,
// which is unusual and worth knowing: file contents are stored as blobs in the
// database rather than beside it, so the database IS the data and the volume must
// be sized for everything you intend to host. Import it and render with kurly.list:
//
//   local picoshare = import 'github.com/metio/kurly/workloads/picoshare/server.libsonnet';
//   kurly.list(picoshare())
//
// Serves the web UI on :4001 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='picoshare',
  image=defaultImage,
  // Sized for the FILES, not for an index: PicoShare keeps uploaded content inside
  // the SQLite database.
  storageSize='20Gi',
  storageClass=null,
  // The Secret holding PS_SHARED_SECRET, the single passphrase that grants upload
  // and administration. PicoShare has one account and this is it, so there is
  // nothing else standing between a visitor and the ability to upload.
  secretName='picoshare',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4001)
  + kurly.servicePort(4001)
  + (if env == {} then {} else kurly.env(env))
  + kurly.envFromSecret(secretName)
  // The image never selects an account; nothing here needs root, so one is named
  // and fsGroup makes the volume writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The image's own command already points the database at /data/store.db, so the
  // volume goes there and no argument has to be overridden.
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // SQLite writes its journal and temporary pages beside the database, but a large
  // upload is streamed through a temporary file first.
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
