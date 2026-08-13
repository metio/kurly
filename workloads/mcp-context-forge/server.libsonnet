// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mcp-context-forge — a registry and proxy that federates MCP servers, A2A
// servers and REST APIs behind one endpoint, with authentication, rate limiting
// and an admin UI. A plain composable kurly.http workload: the registry lives in
// a SQLite database on a PersistentVolume, so a single instance needs no external
// database. Import it and render with kurly.list:
//
//   local forge = import 'github.com/metio/kurly/workloads/mcp-context-forge/server.libsonnet';
//   kurly.list(forge(secretName='mcp-context-forge'))
//
// Serves the gateway, the admin UI and the API on :4444 — compose an exposure
// onto it.
//
// SECRETS: `secretName` is required in any real deployment. It carries
// JWT_SECRET_KEY (which signs the tokens the gateway issues, so a value that
// changes on restart invalidates every one of them) and the platform admin's
// credentials. The gateway also stores the credentials of every upstream server
// it federates, which is what makes the database worth backing up.
//
// WHAT IT REACHES. The gateway's whole job is to call other servers, so it can
// reach whatever the pod can reach — including anything else in the cluster. A
// NetworkPolicy limiting its egress to the servers it is meant to federate is
// worth composing on.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled). Point databaseUrl at PostgreSQL to run more than one.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='mcp-context-forge',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  // A SQLAlchemy URL; the default keeps SQLite on the volume.
  databaseUrl='sqlite:////app/data/mcp.db',
  // A Secret carrying JWT_SECRET_KEY and the platform admin credentials.
  secretName='mcp-context-forge',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4444)
  + kurly.servicePort(4444)
  + kurly.env({ HOST: '0.0.0.0', PORT: '4444', DATABASE_URL: databaseUrl } + env)
  // The uid and gid the image already runs as; fsGroup so the database is
  // writable.
  + kurly.runAs(10001, gid=10001, fsGroup=10001)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '128Mi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
