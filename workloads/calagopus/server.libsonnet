// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// calagopus — a Calagopus panel (a game server management panel: it creates game
// servers on wings nodes, hands their owners a console, files and backups, and
// keeps the accounts and permissions around them). A composable kurly.http
// workload on the official single-binary image, backed by an EXTERNAL PostgreSQL
// and an EXTERNAL Redis/valkey — the cnpg-cluster and valkey workloads provide
// them — with the panel's own data directory on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local calagopus = import 'github.com/metio/kurly/workloads/calagopus/server.libsonnet';
//   kurly.list(calagopus())
//
// Serves the panel and its API on :8000 — compose an exposure onto it.
//
// The panel talks to the wings daemons it manages over the network, so it needs
// egress to wherever those nodes are; a NetworkPolicy that only allows the
// database and the cache leaves every server unreachable from the panel.
//
// Single writer: the data directory is on a ReadWriteOnce volume, so one replica,
// recreated (never rolled). Running a second instance is a deliberate act —
// APP_PRIMARY decides which one runs the background tasks, so exactly one of them
// may have it set.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='calagopus',
  image=defaultImage,
  // The panel's data directory.
  storageSize='5Gi',
  storageClass=null,
  // Whether this instance runs the background tasks (cleanups and schedules).
  // Exactly one instance of a deployment may have it.
  primary=true,
  // Migrate the schema on start. The first boot against a fresh database is
  // therefore slower than the ones after it.
  migrate=true,
  // The Secret holding DATABASE_URL, REDIS_URL and APP_ENCRYPTION_KEY. The
  // encryption key protects the node and server credentials stored in the
  // database, and the project's own compose file ships it as the literal
  // CHANGEME — an instance started with that has its secrets readable by anyone
  // who has read the repository.
  secretName='calagopus',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(
    {
      PORT: '8000',
      APP_DEBUG: 'false',
      APP_PRIMARY: if primary then 'true' else 'false',
      DATABASE_MIGRATE: if migrate then 'true' else 'false',
      APP_LOG_DIRECTORY: '/var/log/calagopus',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The image selects no account and the binary needs nothing root provides.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/lib/calagopus', storageSize, storageClass=storageClass)
  // Logs are written beside the data, not to stdout only, and the root
  // filesystem stays read-only.
  + kurly.scratch('/var/log/calagopus')
  + kurly.scratch('/tmp')
  // The schema is migrated before anything answers on the port.
  + kurly.startupProbe({ httpGet: { path: '/', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
