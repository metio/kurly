// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// openhabittracker — an OpenHabitTracker server (habits, tasks and notes in one
// place, with time tracking, a calendar view and completion statistics). A plain
// composable kurly.http workload keeping its database on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local openhabittracker = import 'github.com/metio/kurly/workloads/openhabittracker/server.libsonnet';
//   kurly.list(openhabittracker())
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// THE PUBLISHED IMAGE IS A BLAZOR SERVER APP FOR EXACTLY ONE USER. The account is
// whatever APPSETTINGS_USERNAME/EMAIL/PASSWORD in the Secret say, there is no
// registration, and there is no second account to add — one instance per person is
// the deployment model, not a limitation of this workload.
//
// Single writer: one database file on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='openhabittracker',
  image=defaultImage,
  // Habits, tasks, notes and their recorded time.
  storageSize='1Gi',
  storageClass=null,
  // The Secret holding APPSETTINGS_USERNAME, APPSETTINGS_EMAIL,
  // APPSETTINGS_PASSWORD and APPSETTINGS_JWT_SECRET — the single account the
  // instance has, and the key signing its sessions.
  secretName='openhabittracker',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + (if env == {} then {} else kurly.env(env))
  + kurly.envFromSecret(secretName)
  // The image declares APP_UID=1654 and creates that account, but never switches to
  // it, and the install tree it writes into is owned by root — running as the
  // account the image names denies every request instead of serving it.
  + kurly.rootUser()
  // The application keeps its data in a directory beside its own code, under the
  // working directory the image sets.
  + kurly.store('/app/.OpenHabitTracker', storageSize, storageClass=storageClass)
  // The request logger opens its own LiteDB file at /app/watchlogs.db — inside the
  // install tree, next to the assemblies, so no emptyDir can be mounted over it
  // without hiding the application. It is opened on the FIRST request rather than
  // at startup, so a read-only root filesystem here does not fail the pod, it
  // fails every request the pod is asked to serve.
  + kurly.writableRootFilesystem()
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
