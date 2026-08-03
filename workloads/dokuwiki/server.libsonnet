// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// dokuwiki — a DokuWiki server (a simple, database-less wiki that stores its pages
// as flat files). A plain composable kurly.http workload on the official image: all
// of its content lives on a PersistentVolume, so it needs no external database.
// Import it and render with kurly.list:
//
//   local dokuwiki = import 'github.com/metio/kurly/workloads/dokuwiki/server.libsonnet';
//   kurly.list(dokuwiki())
//
// Serves the wiki on :80 — compose an exposure onto it.
//
// The nginx + PHP-FPM image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: the flat-file content lives on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='dokuwiki',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // Apache in this image serves on :8080 as the unprivileged web user; the Service
  // keeps :80.
  + kurly.port(8080)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  // The image declares root, but it runs as an ordinary uid: its files are
  // world-readable and everything it writes is under a volume fsGroup owns.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Writes under /var/run/apache2; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/run/apache2')
  // The entrypoint hands /storage to www-data before dropping to it.
  // Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID'])
  + kurly.store('/storage', storageSize, storageClass=storageClass)
  // The entrypoint relinks the bundled plugins and templates onto the volume on
  // every start, which takes a while before anything listens.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
