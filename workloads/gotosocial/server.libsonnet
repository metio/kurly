// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gotosocial — a GoToSocial server (a lightweight, self-hosted ActivityPub/Fediverse
// social server, an alternative to Mastodon that federates with it). A plain composable
// kurly.http workload on the official image; with the default SQLite backend its database
// and stored media live on a PersistentVolume. Import it, adapt with the parameters below,
// and render with kurly.list:
//
//   local gotosocial = import 'github.com/metio/kurly/workloads/gotosocial/server.libsonnet';
//   kurly.list(gotosocial(host='social.example.com'))
//
// Serves the web app, client and federation API on :8080 — compose an exposure onto it.
//
// HOST IS PERMANENT: GoToSocial's host (the domain in every account's @handle) is fixed at
// first run and cannot be changed later, so set it deliberately.
//
// DATABASE: point GoToSocial at an external PostgreSQL (GTS_DB_TYPE=postgres plus the
// GTS_DB_* connection, from a Secret via kurly.envFromSecret) to scale past SQLite.
//
// Single writer: the SQLite database and local media live on a ReadWriteOnce volume, so
// one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='gotosocial',
  image='docker.io/superseriousbusiness/gotosocial:0.20.1',
  storageSize='20Gi',
  storageClass=null,
  // The instance domain — permanent, part of every @handle.
  host=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    {
      GTS_DB_TYPE: 'sqlite',
      GTS_DB_ADDRESS: '/gotosocial/storage/sqlite.db',
      GTS_STORAGE_LOCAL_BASE_PATH: '/gotosocial/storage',
      GTS_LETSENCRYPT_ENABLED: 'false',
    }
    + (if host == null then {} else { GTS_HOST: host });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/gotosocial/storage', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/readyz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/livez', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
