// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kapowarr — a Kapowarr server (a manager for a comic book library: it tracks the
// volumes you follow, downloads the issues it is missing, renames them into your
// naming scheme and converts them between formats). A plain composable kurly.http
// workload keeping its SQLite database and the comic library on PersistentVolumes.
// Import it and render with kurly.list:
//
//   local kapowarr = import 'github.com/metio/kurly/workloads/kapowarr/server.libsonnet';
//   kurly.list(kapowarr())
//
// Serves the web UI and API on :5656 — compose an exposure onto it.
//
// TWO VOLUMES: the database at /app/db is small and the library at the root folder
// is not, so they are sized separately — a library volume large enough for a comic
// collection is the wrong shape for a few megabytes of SQLite. The root folder has
// to be added in Kapowarr's own settings after the first start; kurly mounts it,
// Kapowarr does not learn about it by itself.
//
// DOWNLOADS: in-flight downloads land in /app/temp_downloads and move into the
// library when they finish, so that directory holds nothing worth surviving a
// restart and is an emptyDir with a size limit rather than a third volume. Size it
// past the largest download you expect — a full one fails the download, not the pod.
//
// EGRESS: it fetches metadata from ComicVine and issues from the download sources
// you configure, so the pod needs egress to the internet. A NetworkPolicy written
// from the shape of the manifest blocks it and searches then simply find nothing.
//
// The entrypoint drops privileges with gosu only when PUID is set to something
// other than 0. With the image's default PUID=0 it takes the branch that changes
// no ownership and execs the app as whoever we already are, so this runs as an
// unprivileged user and keeps the hardened default posture — no root, no privilege
// escalation, read-only root filesystem.
//
// Single writer: one SQLite database and one library tree on ReadWriteOnce volumes,
// so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='kapowarr',
  image=defaultImage,
  // The SQLite database, the settings and the download history.
  storageSize='2Gi',
  // The comic library itself — the root folder to register in the settings.
  libraryStorageSize='100Gi',
  libraryMountPath='/comics',
  storageClass=null,
  // The scratch space in-flight downloads occupy before they are moved into the
  // library.
  downloadSizeLimit='10Gi',
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5656)
  + kurly.servicePort(5656)
  + kurly.env({ TZ: timezone } + env)
  // The image creates an unprivileged account but selects none, and with PUID at
  // its default the entrypoint runs the app as whoever we are.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/db', storageSize, storageClass=storageClass)
  + kurly.store(libraryMountPath, libraryStorageSize, storageClass=storageClass)
  // The command writes its log file here (--LogFolder /app/logs) and the process
  // never starts if it cannot; the logs are read through the web UI, not from a
  // volume.
  + kurly.scratch('/app/logs', '256Mi')
  + kurly.scratch('/app/temp_downloads', downloadSizeLimit)
  + kurly.scratch('/tmp')
  // Ask for a connection: the web UI answers / with its own single-page app and a
  // configured instance redirects to a login, so a path probe grades a redirect
  // rather than the server.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
