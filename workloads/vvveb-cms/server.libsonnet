// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// vvveb-cms — a Vvveb CMS server (a content management system with a drag-and-drop
// page builder) on the project's own image, with the whole application tree on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local vvveb = import 'github.com/metio/kurly/workloads/vvveb-cms/server.libsonnet';
//   kurly.list(vvveb())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// FIRST START DOWNLOADS THE APPLICATION. The image ships PHP, nginx and an entry
// point; the CMS itself is fetched from DOWNLOAD_URL into /var/www/html the first
// time the volume is empty, so the first boot needs egress to that host and takes
// far longer than later ones — hence the generous startup probe, and hence the
// volume being mounted at the application root rather than at a data directory.
//
// DATABASE: Vvveb needs a MySQL/MariaDB or PostgreSQL, and it is chosen and
// credentialed in the web installer on first visit, not from env — so kurly passes
// no database coordinates and authors no Secret. Point the installer at the
// mysql-cluster or cnpg-cluster workload.
//
// Single writer: the application tree lives on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='vvveb-cms',
  image=defaultImage,
  // The application tree: code, configuration, themes, uploads and the page cache.
  storageSize='10Gi',
  storageClass=null,
  // Where the entry point fetches the release from on an empty volume. The image's
  // own default is the project's nightly download endpoint; point it at a mirror to
  // deploy without egress to vvveb.com.
  downloadUrl=null,
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
  + kurly.env(
    (if downloadUrl == null then {} else { DOWNLOAD_URL: downloadUrl })
    + env
  )
  // supervisord runs nginx and php-fpm together, and both drop their workers to
  // www-data, which they can only do from root; nginx also binds :80 and the entry
  // point chowns the unpacked tree.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // nginx, php-fpm and supervisord keep their pid files, logs and temporary request
  // bodies inside the image's own tree.
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html', storageSize, storageClass=storageClass)
  // The first boot downloads and unpacks the release before nginx answers anything,
  // so the startup budget is minutes, not seconds. Probing by connection: until the
  // installer has been walked through, every path answers with a redirect to it.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
