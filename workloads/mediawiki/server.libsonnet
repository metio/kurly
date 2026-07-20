// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mediawiki — a MediaWiki server (the wiki engine behind Wikipedia). A plain
// composable kurly.http workload on the official image, backed by an external
// MySQL/MariaDB, with its uploaded files on a PersistentVolume. Import it and render
// with kurly.list:
//
//   local mediawiki = import 'github.com/metio/kurly/workloads/mediawiki/server.libsonnet';
//   kurly.list(mediawiki())
//
// Serves the wiki on :80 — compose an exposure onto it.
//
// CONFIGURATION: MediaWiki is configured by a LocalSettings.php (database
// credentials, secret keys, extensions). Generate it once with the web installer, or
// author it, and mount it at /var/www/html/LocalSettings.php from a Secret (it holds
// the database password and $wgSecretKey) — kurly authors none.
//
// The Apache + PHP image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: uploaded files live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='mediawiki',
  image='docker.io/library/mediawiki:1.45.4',
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
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/images', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
