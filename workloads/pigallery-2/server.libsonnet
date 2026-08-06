// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pigallery-2 — a PiGallery2 server (a directory-first photo gallery: it serves the folder
// tree your photos already live in, with search, faces and a map view). A plain composable
// kurly.http workload on the official image: its SQLite database, generated thumbnails and
// the media library all live under /app/data, so it needs no external database. Import it
// and render with kurly.list:
//
//   local pigallery2 = import 'github.com/metio/kurly/workloads/pigallery-2/server.libsonnet';
//   kurly.list(pigallery2())
//
// Serves the web app on :80 — compose an exposure onto it. The server binds :80 and
// nothing moves it: the port is baked into the image's defaults, and neither the PORT
// environment variable nor a --Server-port argument is read (an added --config-path is
// rejected outright). Binding it needs no privilege — Kubernetes starts a container's
// unprivileged port range at 0 — so the hardened default posture stands.
//
// STORAGE: one PersistentVolume at /app/data holds the config file the app writes at
// startup (/app/data/config), the SQLite database (/app/data/db), the media library it
// scans (/app/data/images) and the temp/thumbnail cache (/app/data/tmp). Size it for the
// library, not for the database.
//
// Single writer: the data volume is ReadWriteOnce, so one replica, recreated (never
// rolled) to keep two pods off the same files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='pigallery-2',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  // The image never creates the directories its entrypoint and defaults name — it opens
  // /app/data/config/config.json for writing and reports the images folder as missing —
  // so the server runs on defaults it can never save. kubelet CREATES a subPath directory
  // that does not exist, so each one is mounted back out of the same volume it lives in.
  local dataDirs = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container {
          volumeMounts+: [
            { name: 'store', mountPath: '/app/data/' + dir, subPath: dir }
            for dir in ['config', 'db', 'images', 'tmp']
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
  // The server binds :80 from the image's baked-in defaults; there is no knob for it.
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // A Service named after the workload injects PIGALLERY_2_PORT as a tcp:// URL into
  // the container; nothing here should be able to read that as a listen address.
  + kurly.disableServiceLinks()
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  // The first start writes a config file and builds the client index before it serves.
  + kurly.startupProbe({ httpGet: { path: '/heartbeat', port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ httpGet: { path: '/heartbeat', port: 'http' }, periodSeconds: 15 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + dataDirs
