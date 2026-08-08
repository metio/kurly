// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gameap — a GameAP panel (the web panel and API that administer game servers running
// on Linux and Windows hosts through the GameAP daemon). A composable kurly.http
// workload on the project's own image: a single static binary, running as the
// unprivileged user the image ships, with its database and uploaded files on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local gameap = import 'github.com/metio/kurly/workloads/gameap/server.libsonnet';
//   kurly.list(gameap())
//
// Serves the panel, the REST API and the WebSocket endpoint on :8025 — compose an
// exposure onto it.
//
// DATABASE: the panel speaks SQLite, PostgreSQL or MySQL/MariaDB. It defaults to
// SQLite on its own volume, so it needs nothing external to start; set
// databaseDriver='postgres' or 'mysql' and let DATABASE_URL come from the Secret,
// since that URL carries the password.
//
// SECRETS: ENCRYPTION_KEY encrypts stored credentials and AUTH_SECRET signs the
// session tokens, both read from a provided Secret via envFrom. kurly authors no
// Secret.
//
// The binary terminates TLS itself when told to; behind an exposure it is left
// serving plain HTTP, so nothing needs a privileged port and the hardened defaults
// (non-root, read-only rootfs, all capabilities dropped) stand as they are.
//
// Single writer: the SQLite database and the uploaded files live on a ReadWriteOnce
// volume, so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='gameap',
  image=defaultImage,
  // The SQLite database, the ACME material and the uploaded files.
  storageSize='5Gi',
  storageClass=null,
  // 'sqlite', 'postgres' or 'mysql'.
  databaseDriver='sqlite',
  // The connection URL. Left null with the sqlite driver it points at the volume;
  // left null with any other driver it must come from the Secret, because the URL
  // carries the password.
  databaseUrl=null,
  // The Secret holding ENCRYPTION_KEY and AUTH_SECRET — and DATABASE_URL when the
  // panel talks to an external server (kurly mints none), via envFrom.
  secretName='gameap',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local dataPath = '/var/lib/gameap';
  local sqliteUrl = 'file:' + dataPath + '/gameap.sqlite?_busy_timeout=5000&_journal_mode=WAL&cache=shared';
  local url =
    if databaseUrl != null then { DATABASE_URL: databaseUrl }
    else if databaseDriver == 'sqlite' then { DATABASE_URL: sqliteUrl }
    else {};

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8025)
  + kurly.servicePort(8025)
  + kurly.env(
    {
      HTTP_HOST: '0.0.0.0',
      HTTP_PORT: '8025',
      DATABASE_DRIVER: databaseDriver,
      FILES_DRIVER: 'local',
      FILES_LOCAL_BASE_PATH: dataPath + '/files',
    }
    + url
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image declares its user by NAME, which kubelet cannot verify against
  // runAsNonRoot — the pod is refused before it starts — so the uid the image
  // creates is named here, with fsGroup so the volume arrives owned by it.
  + kurly.runAs(1000, 1000, fsGroup=1000)
  // A Service named after this workload makes Kubernetes inject GAMEAP_PORT as a
  // tcp:// URL, next to the HTTP_PORT the panel reads out of the same environment.
  + kurly.disableServiceLinks()
  + kurly.store(dataPath, storageSize, storageClass=storageClass)
  // The local file manager opens its base path and panics if it is not there,
  // and an empty volume has nothing but its own root — so the directory is made
  // before the panel starts. It is kept BESIDE the database rather than being
  // the volume root, so a file the panel serves can never be the database.
  // Runs the workload's own image (a busybox shell rides in the alpine base), so
  // kurly.mirror carries it onto a private registry with everything else.
  + kurly.initContainer({
    name: 'create-files-dir',
    image: image,
    command: ['/bin/sh', '-c', 'mkdir -p ' + dataPath + '/files'],
    volumeMounts: [{ name: 'store', mountPath: dataPath }],
  })
  // /api/health is the panel's own health endpoint, answered without authentication.
  + kurly.startupProbe({ httpGet: { path: '/api/health', port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
