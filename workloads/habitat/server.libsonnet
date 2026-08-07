// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// habitat — a Habitat server (a message board for one place: residents post about
// their neighbourhood, and a post can be pinned to a location so people find the
// conversations happening near them). A composable kurly.http workload: a Symfony
// application served by FrankenPHP, backed by an EXTERNAL PostgreSQL — the
// cnpg-cluster workload provides one — with uploaded images on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local habitat = import 'github.com/metio/kurly/workloads/habitat/server.libsonnet';
//   kurly.list(habitat())
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// The Caddy inside FrankenPHP is told to serve plain HTTP on that port, because a
// SERVER_NAME carrying a hostname makes it obtain its own certificate; TLS belongs
// to the exposure, not to the pod.
//
// The entrypoint runs the Doctrine migrations before it serves, so the first start
// on an empty database takes minutes — that is a startup probe's job, never a
// longer liveness delay.
//
// Single writer: uploaded images on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='habitat',
  image=defaultImage,
  // Images attached to posts. The application writes them to /uploads by a
  // hard-coded path.
  storageSize='10Gi',
  storageClass=null,
  // The port Caddy listens on. Unprivileged, so the pod keeps the hardened
  // default posture.
  port=8080,
  // The address the instance is reached at. Symfony generates URLs from it
  // wherever there is no request to derive them from — the links in the mails it
  // sends, above all — so a wrong value sends people somewhere that is not this
  // instance. Left unset it keeps the image's own http://localhost.
  url=null,
  // The Secret holding DATABASE_URL, APP_SECRET, ENCRYPTION_KEY and the two
  // Mercure JWT keys. Every one of them has a published placeholder in the
  // project's compose file, and ENCRYPTION_KEY is what the stored settings are
  // encrypted with — changing it later makes them unreadable.
  secretName='habitat',
  env={},
  resources={ requests: { cpu: '250m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.env(
    {
      SERVER_NAME: ':' + std.toString(port),
      APP_ENV: 'prod',
    }
    + (if url == null then {} else { DEFAULT_URI: url })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image ships its files owned by root and needs nothing root provides at
  // runtime; the volume is handed over by fsGroup.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The frankenphp binary carries the cap_net_bind_service file capability, and
  // execing a file that carries one is REFUSED — with EPERM — both under
  // no-new-privileges and when the capability is outside the bounding set. Either
  // alone kills the container after it has run the migrations, with nothing but
  // "exec: frankenphp: Operation not permitted" to go on. So the capability is
  // granted back on top of the dropped-ALL default and escalation is allowed;
  // everything else stays dropped, and the process is still an unprivileged user
  // listening on an unprivileged port.
  + kurly.allowPrivilegeEscalation()
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  + kurly.store('/uploads', storageSize, storageClass=storageClass)
  // Symfony warms its cache and writes its log beside its own code, and Caddy
  // keeps its state and configuration in the XDG directories the image sets.
  + kurly.scratch('/app/var')
  + kurly.scratch('/data')
  + kurly.scratch('/config')
  + kurly.scratch('/tmp')
  // A Service named habitat injects HABITAT_PORT as a tcp:// URL, which Symfony's
  // dotenv loads over anything the image baked in.
  + kurly.disableServiceLinks()
  // The migrations run before the first byte is served, and the connection probe
  // avoids the redirect to the sign-in page that a path probe would follow.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
