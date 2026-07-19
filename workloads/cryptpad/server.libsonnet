// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cryptpad — a CryptPad server (end-to-end encrypted, collaborative documents,
// spreadsheets, and more). A plain composable kurly.http workload on the official
// image: it keeps its encrypted blocks, blobs, and datastore on a PersistentVolume,
// so it needs no external database. Import it and render with kurly.list:
//
//   local cryptpad = import 'github.com/metio/kurly/workloads/cryptpad/server.libsonnet';
//   kurly.list(cryptpad())
//
// Serves the app on :3000 — compose an exposure onto it.
//
// CONFIGURATION: CryptPad needs a config.js at /cryptpad/config/config.js setting
// httpUnsafeOrigin (the main URL) and httpSafeOrigin (a SEPARATE sandbox domain —
// required for its security model). Mount it with kurly.config; the two origins
// must resolve to this Service.
//
// The Node app writes to several paths under /cryptpad at runtime, so this relaxes
// the read-only-rootfs default while keeping non-root, dropped capabilities, and no
// privilege escalation.
//
// Single writer: the encrypted datastore lives on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='cryptpad',
  image='docker.io/cryptpad/cryptpad:2026.5.1',
  storageSize='10Gi',
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
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/cryptpad/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
