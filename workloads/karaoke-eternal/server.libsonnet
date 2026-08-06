// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// karaoke-eternal — a Karaoke Eternal Server (hosts a karaoke party: the room
// screen plays the songs, guests queue them from their own phone browser). A plain
// composable kurly.http workload: the SQLite database and the media library live on
// PersistentVolumes, so it needs no external database. Import it and render with
// kurly.list:
//
//   local karaokeEternal = import 'github.com/metio/kurly/workloads/karaoke-eternal/server.libsonnet';
//   kurly.list(karaokeEternal())
//
// Serves the room screen and the player UI on :8080 — compose an exposure onto it.
//
// THE FIRST ACCOUNT REGISTERED BECOMES THE ADMINISTRATOR, so on an exposed instance
// that is whoever arrives first. Create it before publishing the URL.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='karaoke-eternal',
  image=defaultImage,
  // The SQLite database and the server's own state, at /config — the path the
  // image's own command line already names.
  storageSize='5Gi',
  storageClass=null,
  // The media library at /mnt/karaoke, the path the app's "add media folder" step
  // expects. Sized for songs, not for state, hence a separate volume: a library
  // outgrows a database by two orders of magnitude, and on shared storage it is
  // often a ReadWriteMany claim filled by something else entirely.
  mediaSize='50Gi',
  mediaStorageClass=null,
  mediaAccessModes=['ReadWriteOnce'],
  // KES_SCAN=1 runs the media scanner at startup; the rest are logging levels.
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // The image's entrypoint is started with `-p 8080`, so this is the port it
  // really binds; the Service publishes the same number rather than remapping it.
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + (if env == {} then {} else kurly.env(env))
  // The image declares no USER, so it would run as root against the hardened
  // default; node's own account owns the volumes instead.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.store('/mnt/karaoke', mediaSize, accessModes=mediaAccessModes, storageClass=mediaStorageClass)
  // The scanner and the media uploads stage files through the system temporary
  // directory, which a read-only root filesystem does not offer.
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
