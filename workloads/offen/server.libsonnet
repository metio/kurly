// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// offen — an Offen Fair Web Analytics server (lightweight, self-hosted web
// analytics where the people being measured can see and delete their own data).
// A plain composable kurly.http workload: events and accounts live in a SQLite
// database on a PersistentVolume, so it needs no external database. Import it
// and render with kurly.list:
//
//   local offen = import 'github.com/metio/kurly/workloads/offen/server.libsonnet';
//   kurly.list(offen())
//
// Serves the collector, the auditorium and the account interface on :3000 —
// compose an exposure onto it.
//
// The image defaults to :80 and gets there with a FILE CAPABILITY
// (CAP_NET_BIND_SERVICE set on the binary), which a container that drops ALL
// capabilities cannot receive — so this stage moves the listener to :3000 and
// keeps the hardened posture instead of relaxing it for a port number.
//
// Single writer: one SQLite file on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the database.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='offen',
  image=defaultImage,
  // The SQLite database of accounts and collected events.
  storageSize='5Gi',
  storageClass=null,
  // The Secret holding OFFEN_SECRET, the key that signs sessions and cookies.
  // Without it Offen mints a random one at startup, so every restart logs
  // everybody out — supplying it is what makes sessions survive a rollout.
  secretName='offen',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(
    {
      OFFEN_SERVER_PORT: '3000',
      OFFEN_DATABASE_DIALECT: 'sqlite3',
      OFFEN_DATABASE_CONNECTIONSTRING: '/var/opt/offen/offen.db',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The image declares uid 10000 / gid 10001; pin them so the fsGroup makes the
  // data volume writable by the user the binary actually runs as.
  + kurly.runAs(10000, gid=10001, fsGroup=10001)
  + kurly.store('/var/opt/offen', storageSize, storageClass=storageClass)
  // Offen keeps its ACME cache beside its own tree even when TLS is terminated
  // elsewhere, and writes temporary files while it exports.
  + kurly.scratch('/var/www/.cache', '32Mi')
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
