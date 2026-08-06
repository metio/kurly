// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// chibisafe-server — the fastify backend of chibisafe: the upload API, the album
// and link bookkeeping, the thumbnailer, and the SQLite database behind all of
// it. It holds every piece of state the installation has.
//
// chibisafe is three coordinated stages — server, frontend and proxy — sharing
// one name prefix and the uploads volume. Run all three and expose the proxy; see
// the workload README.
//
//   local server = import 'github.com/metio/kurly/workloads/chibisafe/server.libsonnet';
//   kurly.list(server())
//
// Serves the API on :8000. It is NOT the stage you expose: the browser talks to
// the proxy, which serves the frontend at / and forwards /api and /docs here.
//
// STORAGE: two volumes, because the two halves grow at completely different
// rates — the uploaded files at /app/uploads (the first store, so its claim is
// <name>-store, which is what the proxy mounts read-only to serve the files) and
// the SQLite database at /app/database. The logs go to an emptyDir: they are
// rotated copies of what the container already prints.
//
// SERVING UPLOADS IS NOT ITS JOB: in production the backend registers no static
// file route at all, so an uploaded file is only reachable through the proxy.
//
// Single writer on one SQLite database, so one replica, recreated (never rolled)
// to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  namePrefix='chibisafe',
  name=null,
  image=defaultImage,
  // The uploaded files. This is the volume that grows.
  storageSize='50Gi',
  storageClass=null,
  // ReadWriteMany lets the proxy read the uploads from another node. With the
  // ReadWriteOnce default both pods must land on the same node.
  accessModes=['ReadWriteOnce'],
  // The SQLite database, which stays small next to the uploads.
  databaseSize='2Gi',
  databaseStorageClass=null,
  // The Secret holding ADMIN_PASSWORD, the password of the `admin` account the
  // backend creates on first start. The consumer provides it; kurly mints none.
  secretName='chibisafe',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-server';

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  // HOST is what the settings fall back to, and its default is `localhost` — a
  // backend nothing outside the pod can reach. The image sets it to 0.0.0.0; it
  // is restated here so a rebuilt or retagged image cannot take it away silently.
  + kurly.env({ HOST: '0.0.0.0', PORT: '8000' } + env)
  + kurly.envFromSecret(secretName)
  + kurly.store('/app/uploads', storageSize, accessModes=accessModes, storageClass=storageClass)
  + kurly.store('/app/database', databaseSize, storageClass=databaseStorageClass)
  // Rotated log files, written beside the code; nothing here is not also on
  // stdout.
  + kurly.scratch('/app/logs', '1Gi')
  + kurly.scratch('/tmp', '1Gi')
  // The start script runs `prisma migrate deploy && prisma generate` before the
  // server binds, and generate writes the client into /app/node_modules — inside
  // the image's own tree, owned by root. That is both why the root filesystem is
  // writable and why the pod runs as root: an ordinary uid cannot write there,
  // and the container exits before it ever listens.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // First start applies the whole migration set and regenerates the Prisma client
  // before anything listens.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  // Every API path wants an API key or a session and answers 401 without one, so
  // probe by connection rather than on a path that would fail forever.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 30, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
