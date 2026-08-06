// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// airtrail — an AirTrail server (a personal flight log: every flight you have
// taken on a world map, with routes, distances, time in the air and the
// statistics that fall out of them, importable from the trackers people already
// use). A composable kurly.http workload backed by an EXTERNAL PostgreSQL — the
// cnpg-cluster workload provides one — with uploaded files on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local airtrail = import 'github.com/metio/kurly/workloads/airtrail/server.libsonnet';
//   kurly.list(airtrail(origin='https://flights.example.com'))
//
// Serves the web application on :3000 — compose an exposure onto it.
//
// SET `origin` TO THE URL PEOPLE WILL VISIT. This is a SvelteKit application, and
// SvelteKit checks the Origin header of every state-changing request against it;
// with the image's default of http://localhost:3000 an exposed instance renders
// pages and refuses every sign-in and every saved flight with a CSRF error, which
// reads as a broken application rather than a misconfigured one.
//
// The entrypoint applies database migrations before it starts the server, so the
// first boot of a fresh database is slower than every later one — that is what the
// startup probe budgets for.
//
// Single writer: uploaded files on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='airtrail',
  image=defaultImage,
  // Uploaded files (airline icons and the like). UPLOAD_LOCATION points here; with
  // no location set the application disables uploads entirely.
  storageSize='5Gi',
  storageClass=null,
  // The public URL the browser reaches this instance at. Every state-changing
  // request is refused unless it matches.
  origin=null,
  // The Secret holding DB_URL, the full PostgreSQL connection string. It carries
  // the password, which is why the whole URL lives in the Secret rather than being
  // assembled from parameters here.
  secretName='airtrail',
  // Detailed flight tracks are submitted inside the flight form, so the request
  // body limit is far above a form's usual size.
  bodySizeLimit='20M',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
                    UPLOAD_LOCATION: '/app/uploads',
                    BODY_SIZE_LIMIT: bodySizeLimit,
                  }
                  + (if origin == null then {} else { ORIGIN: origin });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  // A Service named after the workload injects AIRTRAIL_PORT as a tcp:// URL, and
  // Node reads PORT-shaped variables out of the environment it is handed.
  + kurly.disableServiceLinks()
  // The image runs as the node account (uid/gid 1000) and never drops privileges,
  // so the hardened posture stands; the volume only has to arrive owned by that
  // account for uploads to work.
  + kurly.runAs(1000)
  + kurly.store('/app/uploads', storageSize, storageClass=storageClass)
  // Node writes temporary files while receiving an upload, and the root filesystem
  // stays read-only.
  + kurly.scratch('/tmp')
  // Migrations run before the server listens, so a fresh database makes the first
  // start much longer than the steady-state one.
  + kurly.startupProbe({ httpGet: { path: '/api/ping', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/api/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
