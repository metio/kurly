// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// homegallery — a HomeGallery server (a self-hosted photo and video gallery that indexes the
// folders your media already lives in and offers a timeline, similarity search and face
// detection). A plain composable kurly.http workload on the official image: its config file,
// SQLite-free database file and generated preview storage all live under /data, so it needs no
// external database. Import it and render with kurly.list:
//
//   local homegallery = import 'github.com/metio/kurly/workloads/homegallery/server.libsonnet';
//   kurly.list(homegallery())
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// STORAGE: one PersistentVolume at /data. The image sets HOME, GALLERY_BASE_DIR and
// GALLERY_CACHE_DIR to /data and GALLERY_CONFIG_DIR to /data/config, so the configuration
// (written on first start, since none exists), the database file and the preview storage all
// land there — and so does the media itself, under /data/Pictures by default. Size the volume
// for the library, not for the database.
//
// ARGS: the image's entrypoint is `node /app/gallery.js` and carries no default command, so the
// stage passes `run server` — the subcommand that starts the web server and imports and watches
// the source directories. Without it the process prints usage and exits.
//
// API SERVER: similarity search and face detection are computed by a separate embedding API.
// apiServer points at one (the project runs a public instance, which the image's own default
// uses); set it to your own xemle/home-gallery-api-server to keep the media in the cluster.
//
// The server needs no privilege: it binds :3000 as the image's own node user, so it runs as
// 1000:1000 with a read-only root filesystem, and only /tmp is writable — ffmpeg and vips write
// their temporary files there while generating previews.
//
// First start writes a configuration and then imports the whole library before the web app
// answers, which on a large library is slow: the startup probe carries that wait rather than a
// stretched liveness delay.
//
// Single writer: the database and preview storage sit on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the same files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='homegallery',
  image=defaultImage,
  storageSize='100Gi',
  storageClass=null,
  // The media directories to index, named in the configuration the init container writes.
  // They live on the same volume as everything else, so add photos under them.
  sources=['/data/Pictures'],
  // The embedding API used for similarity search and face detection. Null leaves the image's
  // own default in place; point it at your own api-server to keep the media in the cluster.
  apiServer=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // The server binds :3000; the image exposes the same port.
  + kurly.port(3000)
  + kurly.servicePort(3000)
  // The entrypoint is the CLI itself, so the subcommand is the container's args.
  + kurly.args(['run', 'server'])
  + kurly.env(
    (if apiServer != null then { GALLERY_API_SERVER: apiServer } else {})
    + env
  )
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // A Service named after the workload injects HOMEGALLERY_PORT as a tcp:// URL into the
  // container; nothing here should be able to read that as a listen address.
  + kurly.disableServiceLinks()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // `run server` REFUSES to start when the configuration file is missing — it does not
  // write one — so an empty volume crash-loops the pod on its first boot. `run init`
  // writes it, naming the media directories to index; it is skipped when the file is
  // already there, since re-running it would need --force and would discard the sources
  // and settings edited since.
  + kurly.initContainer({
    name: 'init-config',
    image: image,
    command: [
      'sh',
      '-c',
      'mkdir -p ' + std.join(' ', sources) +
      '; [ -f "$GALLERY_CONFIG" ] || node /app/gallery.js run init ' +
      std.join(' ', ['--source ' + s for s in sources]),
    ],
    volumeMounts: [{ name: 'store', mountPath: '/data' }],
  })
  // ffmpeg and vips write temporary files while generating previews.
  + kurly.scratch('/tmp')
  // First start writes the configuration and imports the library before it serves.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' }, periodSeconds: 15 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
