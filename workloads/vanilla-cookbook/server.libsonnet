// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// vanilla-cookbook — a Vanilla Cookbook server (a recipe manager that imports
// recipes from other cookbook applications and from the web). A plain composable
// kurly.http workload on the official image, keeping its SQLite database and its
// uploaded images on PersistentVolumes. Import it and render with kurly.list:
//
//   local cookbook = import 'github.com/metio/kurly/workloads/vanilla-cookbook/server.libsonnet';
//   kurly.list(cookbook(origin='https://recipes.example.com'))
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// ORIGIN is the one setting the application cannot infer: SvelteKit checks it
// against the request when a form is submitted, and a wrong value turns every
// login and every save into a rejected cross-site request. It defaults to a
// localhost URL so a default render boots — point it at the real host.
//
// TWO volumes, because the application keeps its data in two places and a single
// mount would leave one of them on the container filesystem: the SQLite database
// under /app/prisma/db, and uploaded recipe images and import files under
// /app/uploads.
//
// It runs as root with a writable root filesystem and its capabilities kept: the
// entrypoint creates the data directories, aligns the application user with
// PUID/PGID and chowns both volumes before handing over to that user with gosu,
// and it starts a cron daemon for the scheduled database backup. None of that
// works as an unprivileged user on a read-only filesystem, and the entrypoint
// fails the container rather than continuing.
//
// Single writer: the database and the uploads are on ReadWriteOnce volumes, so
// one replica, recreated (never rolled) to keep two pods off the same files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='vanilla-cookbook',
  image=defaultImage,
  storageSize='2Gi',
  uploadsSize='5Gi',
  storageClass=null,
  // The public URL the application is reached at; SvelteKit validates form
  // submissions against it.
  origin='http://localhost:3000',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if origin == null then {} else { ORIGIN: origin };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(baseEnv + env)
  // The entrypoint chowns both volumes and drops to the application user with
  // gosu; the cron daemon it starts for the scheduled backup wants root too.
  + kurly.rootUser()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  // The SQLite database.
  + kurly.store('/app/prisma/db', storageSize, storageClass=storageClass)
  // Uploaded recipe images and the files an import is read from.
  + kurly.store('/app/uploads', uploadsSize, storageClass=storageClass)
  // The application answers / with its own page, but a wrong ORIGIN makes that a
  // redirect; both probes ask the port instead so a misconfiguration shows up in
  // the browser rather than as a pod that never becomes ready.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  // The first boot runs the Prisma migrations before the server listens.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
