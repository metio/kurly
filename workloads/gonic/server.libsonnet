// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gonic — a gonic server (a music streaming server speaking the Subsonic API, so
// the Subsonic/Airsonic clients you already use work against it). A plain
// composable kurly.http workload on the official image: it keeps its SQLite
// database, cache, podcasts and playlists on a PersistentVolume and reads the
// music library from the same volume, so it needs no external database. Import it
// and render with kurly.list:
//
//   local gonic = import 'github.com/metio/kurly/workloads/gonic/server.libsonnet';
//   kurly.list(gonic())
//
// Serves the web UI and Subsonic API on :8080 — compose an exposure onto it. Put
// your music under the volume's music/ directory.
//
// The image listens on :80 by default, which an unprivileged process cannot bind;
// the stage moves it to :8080 (GONIC_LISTEN_ADDR) rather than granting
// NET_BIND_SERVICE, and runs as an ordinary user.
//
// Every gonic setting is read from a GONIC_-prefixed environment variable, so the
// Service link variables Kubernetes injects for a Service named `gonic`
// (GONIC_PORT=tcp://…) land in the same namespace as its own configuration —
// service links are therefore off.
//
// Single writer: the database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='gonic',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  port=8080,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  // The music library, the cache, the podcasts and the playlists live beside the
  // database on the one volume; kubelet creates each subPath directory, so gonic
  // finds every path it is told about.
  local library = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container {
          volumeMounts+: [
            { name: 'store', mountPath: '/music', subPath: 'music', readOnly: true },
            { name: 'store', mountPath: '/cache', subPath: 'cache' },
            { name: 'store', mountPath: '/podcasts', subPath: 'podcasts' },
            { name: 'store', mountPath: '/playlists', subPath: 'playlists' },
          ],
        }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.disableServiceLinks()
  + kurly.env({
    GONIC_LISTEN_ADDR: ':' + std.toString(port),
    GONIC_DB_PATH: '/data/gonic.db',
    GONIC_MUSIC_PATH: '/music',
    GONIC_CACHE_PATH: '/cache',
    GONIC_PODCAST_PATH: '/podcasts',
    GONIC_PLAYLISTS_PATH: '/playlists',
  } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  // The web root answers a redirect to the login page and every other path wants a
  // session, so both probes ask for a connection instead of a status code.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + library
