// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pinchflat — a Pinchflat server (an automated YouTube archiver built on yt-dlp:
// point it at channels or playlists and it downloads new uploads on a schedule,
// naming and tagging them for a media server to pick up). A plain composable
// kurly.http workload: its SQLite database and the downloaded media live on
// PersistentVolumes. Import it and render with kurly.list:
//
//   local pinchflat = import 'github.com/metio/kurly/workloads/pinchflat/server.libsonnet';
//   kurly.list(pinchflat())
//
// Serves the web UI on :8945 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file and two schedulers off
// the same downloads.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='pinchflat',
  image=defaultImage,
  // Downloaded media. Sized separately from the database because it is the half
  // that grows without limit — a few subscribed channels fill tens of gigabytes.
  mediaSize='100Gi',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8945)
  + kurly.servicePort(8945)
  + kurly.env({ TZ: 'UTC' } + env)
  // The image runs as root and needs nothing root provides: the port is above
  // 1024, and everything it writes is on a volume.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.store('/downloads', mediaSize, storageClass=storageClass)
  // yt-dlp stages each download as a temporary file before muxing it, and
  // pinchflat refuses to start unless /etc/yt-dlp is writable too — it checks every
  // path it uses up front and exits on the first read-only one, reporting
  // `Permissions check failed: {:error, :erofs}` and then "Unknown error". The
  // directory holds no configuration worth keeping (an empty plugins/ tree), so an
  // emptyDir satisfies the check without hiding anything.
  + kurly.scratch('/tmp')
  + kurly.scratch('/etc/yt-dlp')
  + kurly.readinessProbe({ httpGet: { path: '/healthcheck', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthcheck', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
