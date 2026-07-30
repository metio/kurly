// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// baserow — a Baserow server (an open-source, no-code database and Airtable
// alternative). A plain composable kurly.http workload on the official ALL-IN-ONE
// image, which bundles the backend, the web frontend, Celery workers, and (by
// default) an embedded PostgreSQL and Redis — everything in /baserow/data on a
// PersistentVolume, so a single instance needs nothing external. Import it and render
// with kurly.list:
//
//   local baserow = import 'github.com/metio/kurly/workloads/baserow/server.libsonnet';
//   kurly.list(baserow(publicUrl='https://baserow.example.com'))
//
// Serves the web app and API on :80 — compose an exposure onto it. Point
// DATABASE_* / REDIS_* at external services through env (and a Secret) to scale past
// the embedded single instance.
//
// The all-in-one image supervises multiple processes (including the embedded
// database) and writes across the root filesystem, so this relaxes kurly's non-root
// and read-only-rootfs defaults while keeping dropped capabilities and no privilege
// escalation.
//
// Single writer: everything lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the data.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='baserow',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The public URL Baserow builds links against (required).
  publicUrl=null,
  // The Secret holding BASEROW_SECRET_KEY and BASEROW_JWT_SIGNING_KEY (kurly mints
  // none), via envFrom.
  secretName='baserow',
  env={},
  // The all-in-one image runs the Django backend, the Nuxt frontend, celery and
  // its export worker, and caddy in ONE container. At a 2Gi limit it is OOMKilled
  // partway through its first-boot migrations, restarts, starts them again and
  // never converges — the deploy does not run slowly, it never finishes. 4Gi is
  // what upstream recommends for this image and what it takes to get through them.
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    BASEROW_DATA_DIR: '/baserow/data',
  } + (if publicUrl == null then {} else { BASEROW_PUBLIC_URL: publicUrl });

  // The host caddy will serve, taken from publicUrl: everything after the scheme
  // and before the first path separator, so 'https://baserow.example.com/' becomes
  // 'baserow.example.com'. The readiness probe sends it as its Host header,
  // because caddy answers 404 to any other.
  local publicHost =
    if publicUrl == null then null
    else
      local afterScheme =
        local parts = std.splitLimit(publicUrl, '://', 1);
        if std.length(parts) > 1 then parts[1] else parts[0];
      std.splitLimit(afterScheme, '/', 1)[0];

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  // The all-in-one image starts as root, chowns its data dirs, and drops to its
  // own user via gosu — so it needs CAP_CHOWN/SETGID kept and privilege escalation.
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/baserow/data', storageSize, storageClass=storageClass)
  // Readiness has to go through caddy on 80 AND name the host caddy serves.
  //
  // Two facts force it. The backend's own port (8000) listens on loopback only, so
  // a kubelet probe against the pod IP is refused outright — reachable from inside
  // the container and nowhere else. And caddy serves exactly one site, matched on
  // BASEROW_PUBLIC_URL's host, answering 404 to every other Host header; a kubelet
  // httpGet sends the pod IP as Host, which never matches. So a probe through
  // caddy without the header is 404 forever, and a probe around caddy is refused
  // forever, whatever the app is doing.
  //
  // With no publicUrl there is no site to name and /api is not routed at all, so
  // readiness falls back to a connection check — the most that can honestly be
  // asserted about a deployment that has not been told its own address.
  //
  // failureThreshold is large because the backend migrates before it serves, which
  // takes upwards of ten minutes on a cold database: 60 x 15s. Liveness stays a
  // tcpSocket, so a slow migration is never mistaken for a dead container.
  + kurly.readinessProbe(
    (if publicHost == null
     then { tcpSocket: { port: 'http' } }
     else { httpGet: { path: '/api/_health/', port: 'http', httpHeaders: [{ name: 'Host', value: publicHost }] } })
    + { initialDelaySeconds: 30, periodSeconds: 15, failureThreshold: 60 }
  )
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 60 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
