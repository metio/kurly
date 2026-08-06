// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// medama-analytics — a Medama server (privacy-first website analytics: a tracker
// under a kilobyte that sets no cookie and keeps no IP address, with a dashboard
// over the results). A plain composable kurly.http workload keeping both of its
// embedded databases — a SQLite application database and a DuckDB analytics
// database — on a PersistentVolume. Import it and render with kurly.list:
//
//   local medama = import 'github.com/metio/kurly/workloads/medama-analytics/server.libsonnet';
//   kurly.list(medama())
//
// Serves the dashboard, the API and the tracker script on :8080 — compose an
// exposure onto it. The tracker is loaded by the browsers visiting the sites
// being measured, so this is one of the few workloads whose exposure has to be
// reachable from the public internet to do its job at all.
//
// AUTO_SSL is deliberately not wired: it makes the process bind :80 and :443 and
// obtain certificates itself, which is the ingress controller's job here.
//
// HOME is pointed at the volume because DuckDB resolves its extension directory
// under $HOME and the root filesystem is read-only; the ICU extension it loads
// at boot is compiled in, so nothing is downloaded, but the directory is still
// created.
//
// The first boot seeds a single account, `admin` with the password
// CHANGE_ME_ON_FIRST_LOGIN. Anyone who reaches the dashboard before you do owns
// the instance, so change it immediately after the first deploy.
//
// Single writer: two embedded databases on a ReadWriteOnce volume, so one
// replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='medama-analytics',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // Comma-separated origins allowed to call the API routes, for a dashboard
  // hosted somewhere other than this server.
  corsAllowedOrigins=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    {
      PORT: '8080',
      APP_DATABASE_HOST: '/app/data/me_app.db',
      ANALYTICS_DATABASE_HOST: '/app/data/me_analytics.db',
      HOME: '/app/data',
      LOGGER: 'json',
    }
    + (if corsAllowedOrigins == null then {} else { CORS_ALLOWED_ORIGINS: corsAllowedOrigins })
    + env
  )
  // Everything is configured through the environment here, so the Docker-style
  // link variables Kubernetes injects for a Service named after this workload
  // are switched off rather than relied upon to keep missing.
  + kurly.disableServiceLinks()
  // The image declares user 0 and needs nothing root provides: one static
  // binary, no entrypoint dropping privileges, no writes outside the volume.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  // DuckDB spills to the temporary directory when a query outgrows memory.
  + kurly.scratch('/tmp')
  // The dashboard redirects an unauthenticated browser and the API answers a
  // session cookie, so an HTTP probe would be asking about the authentication
  // rather than about the server.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
