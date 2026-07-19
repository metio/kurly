// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// komga — a Komga server (a media server for comics, manga, and digital books). A
// plain composable kurly.http workload on the official image: it keeps its database
// and thumbnails and reads its library from a PersistentVolume, so it needs no
// external database. Import it and render with kurly.list:
//
//   local komga = import 'github.com/metio/kurly/workloads/komga/server.libsonnet';
//   kurly.list(komga())
//
// Serves the web UI, OPDS, and API on :25600 — compose an exposure onto it. Put your
// comic/book library under /books on the volume.
//
// The Java app writes temp files to the root filesystem, so this relaxes the
// read-only-rootfs default while keeping non-root, dropped capabilities, and no
// privilege escalation.
//
// Single writer: the database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='komga',
  image='docker.io/gotson/komga:1.25.0',
  storageSize='20Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  // Komga's database lives at /config; the library it serves lives at /books.
  // Surface the library as a subpath of the same volume.
  local library = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [{ name: 'store', mountPath: '/books', subPath: 'books' }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(25600)
  + kurly.servicePort(25600)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/actuator/health', port: 'http' }, initialDelaySeconds: 20, periodSeconds: 15, failureThreshold: 12 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + library
