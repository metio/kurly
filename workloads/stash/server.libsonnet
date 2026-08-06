// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// stash — a Stash server (an organiser and player for a personal video library:
// it indexes the files you point it at, scrapes metadata for them and serves a
// web player over the result). A plain composable kurly.http workload keeping its
// SQLite database, configuration and generated artefacts on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local stash = import 'github.com/metio/kurly/workloads/stash/server.libsonnet';
//   kurly.list(stash())
//
// Serves the web UI and GraphQL API on :9999 — compose an exposure onto it.
//
// The image defaults every path to /root/.stash and so expects to run as root.
// Every one of those paths is an environment variable, so this stage points them
// all at the volume instead and runs as an unprivileged user.
//
// Media lives under /data/media: mount your library there (a subPath of the same
// volume, or a second volume composed on) — an empty library is not an error,
// Stash simply finds nothing to scan.
//
// Scanning, transcoding and metadata scraping are what this workload spends its
// time on; the resource requests here carry an idle server, and a library scan
// will want considerably more.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='stash',
  image=defaultImage,
  storageSize='100Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9999)
  + kurly.servicePort(9999)
  // Every path the image defaults into /root/.stash, moved onto the volume so the
  // server needs no home directory it cannot write and no root to write it.
  + kurly.env({
    STASH_CONFIG_FILE: '/data/config.yml',
    STASH_STASH: '/data/media',
    STASH_GENERATED: '/data/generated',
    STASH_METADATA: '/data/metadata',
    STASH_CACHE: '/data/cache',
    STASH_BLOBS: '/data/blobs',
    STASH_PORT: '9999',
    HOME: '/data',
  })
  + (if env == {} then {} else kurly.env(env))
  // A Service named stash makes Kubernetes inject STASH_PORT as a tcp:// URL,
  // which is the variable the server reads for its listen port.
  + kurly.disableServiceLinks()
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // ffmpeg and the Python scrapers both write scratch files outside the volume.
  + kurly.scratch('/tmp')
  // A fresh server answers / with the setup wizard and a configured one redirects
  // to a login, so the connection is what a probe can ask about without the answer
  // depending on how far through setup somebody is.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
