// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tubesync — a TubeSync server (subscribe to YouTube channels and playlists and it
// downloads new uploads on a schedule, naming and tagging them so Plex or Jellyfin
// picks them up as a library). A plain composable kurly.http workload with two
// PersistentVolumes: a small one for its database and configuration, and a large
// one for the media. Import it and render with kurly.list:
//
//   local tubesync = import 'github.com/metio/kurly/workloads/tubesync/server.libsonnet';
//   kurly.list(tubesync())
//
// Serves the web UI on :4848 — compose an exposure onto it.
//
// It is an s6-overlay image whose init runs as root, prepares both directories for
// its own account and drops to it — so this workload is deliberately less hardened
// than most here, in the same shape as the other LinuxServer-style images in this
// catalogue.
//
// Single writer: one database on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) — and also because two schedulers would fetch the same videos
// twice.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='tubesync',
  image=defaultImage,
  // Downloaded media, which is the half that grows without limit.
  mediaSize='200Gi',
  storageSize='5Gi',
  storageClass=null,
  // The uid and gid the media is written as, so a media server sharing the volume
  // can read it.
  puid=1000,
  pgid=1000,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4848)
  + kurly.servicePort(4848)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: 'UTC' } + env)
  // s6-overlay: the init runs as root, prepares /config and /downloads for the app
  // account and drops to it, with no path through as an unprivileged process.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // The image writes its caches under /config (XDG_CACHE_HOME and friends already
  // point there), but s6 itself stages state beside the root filesystem.
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.store('/downloads', mediaSize, storageClass=storageClass)
  // A first start migrates the database and builds the static assets.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
