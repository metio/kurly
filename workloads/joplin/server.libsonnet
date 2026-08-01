// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// joplin — a Joplin Server (the self-hosted sync target for the Joplin note-taking apps:
// your notes and notebooks sync through it across devices, end-to-end encrypted). A plain
// composable kurly.http workload on the official image, backed by an external PostgreSQL.
// Import it, point it at a database, and render with kurly.list:
//
//   local joplin = import 'github.com/metio/kurly/workloads/joplin/server.libsonnet';
//   kurly.list(joplin(appBaseUrl='https://joplin.example.com'))
//
// Serves the sync API on :22300 — compose an exposure onto it.
//
// DATABASE & SECRETS: Joplin Server reads its PostgreSQL connection (POSTGRES_*) from the
// environment. kurly authors no Secret; provide one holding them, pulled in via envFrom.
// The defaults pair with a cnpg-cluster named joplin-db.
//
// Stateless: notes live in PostgreSQL, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='joplin',
  image=defaultImage,
  replicas=2,
  appBaseUrl=null,
  // The PostgreSQL it stores notes and users in; the password comes from the Secret.
  dbHost='joplin-db-rw',
  dbPort=5432,
  dbName='joplin',
  dbUser='joplin',
  secretName='joplin',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    {
      APP_PORT: '22300',
      DB_CLIENT: 'pg',
      POSTGRES_HOST: dbHost,
      POSTGRES_PORT: std.toString(dbPort),
      POSTGRES_DATABASE: dbName,
      POSTGRES_USER: dbUser,
    }
    + (if appBaseUrl == null then {} else { APP_BASE_URL: appBaseUrl });
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(22300)
  + kurly.servicePort(22300)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  // The image's own joplin account owns everything the server writes.
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.scratch('/tmp', '64Mi')
  // The process manager keeps its own logs and runtime state under /opt/pm2, which
  // the image owns as root.
  + kurly.scratch('/opt/pm2', '64Mi')
  // It creates working directories inside its own install tree on start — logs
  // first, then temp — and the image ships neither, so scratches there hide nothing
  // of the 18 entries beside them. Both are listed rather than discovered one boot
  // at a time.
  + kurly.scratch('/home/joplin/packages/server/logs', '64Mi')
  + kurly.scratch('/home/joplin/packages/server/temp', '256Mi')
  // The server answers only requests whose origin matches APP_BASE_URL, and the
  // kubelet probes by pod IP — so readiness is a connection check.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
