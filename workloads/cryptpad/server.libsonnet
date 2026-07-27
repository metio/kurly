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
// required for its security model). Mount your own with kurly.config; without one
// the image writes a starter config from mainDomain/sandboxDomain on first start.
// The two origins must resolve to this Service.
//
// The Node app writes to several paths under /cryptpad at runtime, so this relaxes
// the read-only-rootfs default while keeping non-root, dropped capabilities, and no
// privilege escalation.
//
// Single writer: the encrypted datastore lives on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='cryptpad',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  mainDomain='http://localhost:3000',
  sandboxDomain='http://localhost:3001',
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
  // CPAD_CONF is where the app reads its config, and the two domains seed the
  // starter config the image writes when that file does not exist yet.
  + kurly.env({
    CPAD_CONF: '/cryptpad/config/config.js',
    CPAD_MAIN_DOMAIN: mainDomain,
    CPAD_SANDBOX_DOMAIN: sandboxDomain,
  } + env)
  // The image's own cryptpad user owns /cryptpad and everything under it.
  + kurly.runAs(4001, gid=4001, fsGroup=4001)
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
