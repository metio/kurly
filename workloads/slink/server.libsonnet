// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// slink — a Slink server (an image sharing platform: upload a picture, get a
// link, and decide who may follow it, with albums, expiring and password-protected
// shares). A plain composable kurly.http workload on the official image: the
// SQLite databases and the uploaded images live on PersistentVolumes, so it needs
// no external database. Import it and render with kurly.list:
//
//   local slink = import 'github.com/metio/kurly/workloads/slink/server.libsonnet';
//   kurly.list(slink(origin='https://images.example.com'))
//
// Serves the web client on :3000, which proxies /api and /image to the PHP API
// listening on :8080 inside the pod — compose an exposure onto :3000. The API port
// is deliberately not published: the client is the front door.
//
// SET `origin` TO THE URL PEOPLE WILL VISIT. SvelteKit checks the Origin header of
// every form submission against it, so with the image's default of
// http://localhost:3000 an exposed instance serves pages and rejects every upload
// and every login with a CSRF error — a failure that looks like the application is
// broken rather than misconfigured.
//
// STORAGE: two volumes, because the two halves grow at completely different rates
// — the uploaded images at /app/slink/images (the first store, so its claim keeps
// the <name>-store name) and the SQLite databases plus the generated JWT keypair
// at /app/var/data. The keypair is generated on first start and signs every
// session, so losing that volume signs everyone out and cannot be undone by
// restoring the images alone.
//
// Single writer on SQLite, so one replica, recreated (never rolled) to keep two
// pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='slink',
  image=defaultImage,
  // The uploaded images. This is the volume that grows.
  storageSize='50Gi',
  storageClass=null,
  // The SQLite databases and the generated keys, which stay small next to the
  // images.
  dataSize='5Gi',
  dataStorageClass=null,
  // The public URL the browser reaches this instance at. Every state-changing
  // request is refused unless it matches.
  origin=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
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
  // A Service named after the workload injects SLINK_PORT as a tcp:// URL, and the
  // startup scripts read the environment they are handed.
  + kurly.disableServiceLinks()
  // The entrypoint generates the JWT keypair, hands the storage tree to the slink
  // account and drops privileges to it through s6 — all of which it can only do
  // starting from root.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // supervisord, Caddy and the Symfony cache all write inside the image's own tree,
  // and the generated keypair is installed into /services/api/config/jwt.
  + kurly.writableRootFilesystem()
  + kurly.store('/app/slink/images', storageSize, storageClass=storageClass)
  + kurly.store('/app/var/data', dataSize, storageClass=dataStorageClass)
  // First start generates a 4096-bit RSA keypair and migrates two databases before
  // anything listens, so the budget is a startup probe rather than a slack liveness
  // delay. Probing by connection: the client answers / with a redirect once it is
  // up, and a probe that follows one would restart the pod forever.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
