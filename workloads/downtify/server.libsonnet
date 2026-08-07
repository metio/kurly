// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// downtify — a Downtify server (paste a Spotify track, album or playlist link and
// it finds the audio on YouTube Music, converts it with ffmpeg and writes it out
// with album art and metadata attached). A plain composable kurly.http workload:
// the music and its own small database live on PersistentVolumes, and it needs no
// external service and no API key. Import it and render with kurly.list:
//
//   local downtify = import 'github.com/metio/kurly/workloads/downtify/server.libsonnet';
//   kurly.list(downtify())
//
// Serves the web app and API on :8000 — compose an exposure onto it.
//
// TWO VOLUMES, because the two things it writes grow at completely different
// rates: /downloads is the music library, which is unbounded, and /data holds
// settings.json plus the small SQLite database behind playlist monitoring.
//
// Single writer: files and SQLite on ReadWriteOnce volumes, so one replica,
// recreated (never rolled) — and two schedulers monitoring the same playlists
// would download every new track twice.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='downtify',
  image=defaultImage,
  // The music library. Sized separately from the database because it is the half
  // that grows without limit — a few subscribed playlists fill tens of gigabytes.
  mediaSize='100Gi',
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { cpu: '2', memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env({ DOWNTIFY_PORT: '8000' } + env)
  // The entrypoint execs the server directly — the image carries su-exec but
  // never reaches for it — so there is no privilege to drop and the hardened
  // default stands: an unprivileged account writing only to its volumes.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/downloads', mediaSize, storageClass=storageClass)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // yt-dlp and ffmpeg stage each track as a temporary file before the tags are
  // written onto it.
  + kurly.scratch('/tmp')
  // /api/version answers unauthenticated and touches neither disk nor network,
  // which the SPA at / does not: it is served as a static file and a redirect or
  // a rewrite in front of it would decide the pod's fate instead of the app.
  + kurly.readinessProbe({ httpGet: { path: '/api/version', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/version', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
