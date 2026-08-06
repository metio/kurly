// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// chhoto-url — a Chhoto URL server (a small self-hosted URL shortener with a web
// interface and an HTTP API). A plain composable kurly.http workload keeping its
// SQLite database on a PersistentVolume. Import it and render with kurly.list:
//
//   local chhoto = import 'github.com/metio/kurly/workloads/chhoto-url/server.libsonnet';
//   kurly.list(chhoto())
//
// Serves the web app, the API and the redirects on :4567 — compose an exposure
// onto it.
//
// The image is FROM scratch around one static musl binary, so there is nothing to
// relax: no shell, no entrypoint dropping privileges, no writes outside the
// volume. It keeps the fully restricted posture.
//
// CHHOTO_PASSWORD is what guards the admin interface, and an unset one leaves it
// open, so the Secret is not optional in any deployment reachable by anyone.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='chhoto-url',
  image=defaultImage,
  storageSize='1Gi',
  storageClass=null,
  // The Secret holding CHHOTO_PASSWORD (the admin password) and, if the CLI is
  // used, CHHOTO_API_KEY.
  secretName='chhoto-url',
  // The public URL the shortened links are built from. Absent, the frontend
  // shows the links against whatever host the browser used, which is right often
  // enough to hide that it is a guess.
  siteUrl=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4567)
  + kurly.servicePort(4567)
  + kurly.env(
    {
      CHHOTO_DB_URL: '/data/urls.sqlite',
      CHHOTO_LISTEN_PORT: '4567',
      // WAL mode writes a second and a third file beside the database; both live
      // on the volume, and the upstream documentation recommends it.
      CHHOTO_SQLITE_USE_WAL_MODE: 'True',
    }
    + (if siteUrl == null then {} else { CHHOTO_SITE_URL: siteUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The Service is named after the workload, so Kubernetes injects
  // CHHOTO_URL_PORT=tcp://… into a process that reads every one of its settings
  // from a CHHOTO_ variable. Nothing is read under that name today; the links
  // are switched off rather than relied upon to keep missing.
  + kurly.disableServiceLinks()
  // The binary neither selects an account nor needs anything root provides.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // The admin interface answers a browser and the API answers a key, so an HTTP
  // probe would be asking about the authentication rather than about the server.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
