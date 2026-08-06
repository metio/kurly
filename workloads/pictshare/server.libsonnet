// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pictshare — a PictShare server (image, video and paste hosting with a resizing
// URL API: the size, rotation and format are path segments, so a link asks for
// what it needs and the server produces it). A plain composable kurly.http
// workload keeping the uploaded files on a PersistentVolume. Import it and render
// with kurly.list:
//
//   local pictshare = import 'github.com/metio/kurly/workloads/pictshare/server.libsonnet';
//   kurly.list(pictshare())
//
// Serves on :80 — compose an exposure onto it.
//
// ANYONE WHO CAN REACH IT CAN UPLOAD, unless UPLOAD_CODE or ALLOWED_SUBNET says
// otherwise. That is PictShare's design, not an oversight, and on an exposed
// instance it is an open file host with your storage bill attached — so the
// Secret this stage reads is the difference between a private service and a
// public one.
//
// Deliberately less hardened, and for once every reason is in one startup script:
// the entrypoint rewrites php.ini in place, writes its configuration into the
// application tree (src/inc/config.inc.php), creates and chmods /app/public/tmp,
// and starts a local redis-server whose socket lives under /run — so the root
// filesystem is writable. Caddy binds :80, which needs NET_BIND_SERVICE granted
// back on top of the dropped-ALL default; the binary carries the file capability,
// but file capabilities are worthless when the bounding set does not hold it.
//
// The redis it starts is a CACHE INSIDE THE POD, not a dependency — it is not on
// the volume, so it is rebuilt after every restart, and REDIS_CACHING=false in env
// turns it off.
//
// Single writer: one uploads directory on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='pictshare',
  image=defaultImage,
  storageSize='20Gi',
  storageClass=null,
  // The Secret holding UPLOAD_CODE, MASTER_DELETE_CODE and ADMIN_PASSWORD — who
  // may upload, who may delete anything, and who reaches the admin page. Without
  // it the first two are empty, which PictShare reads as "no code required".
  secretName='pictshare',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '768Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  // The image's own default points PHP at a unix socket AND a port, and phpredis
  // reads a socket path as a hostname the moment a port comes with it — the page
  // then fails with getaddrinfo on a path. The project's own compose file names
  // the loopback address and the port instead, which is what the redis the
  // entrypoint starts is actually listening on. Anything in env wins.
  + kurly.env({ REDIS_SERVER: 'localhost', REDIS_PORT: '6379' } + env)
  + kurly.envFromSecret(secretName)
  // The entrypoint edits php.ini, writes its config into the application tree,
  // chmods a directory it creates there, and runs redis-server — all as root.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // Caddy listens on :80, and the redis the entrypoint starts writes its log and
  // its dump into directories the image gives to the redis account — which root
  // may only enter with DAC_OVERRIDE, since dropping ALL takes that from root too.
  // Everything else stays dropped.
  + kurly.addCapabilities(['NET_BIND_SERVICE', 'DAC_OVERRIDE'])
  + kurly.store('/app/public/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
