// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// xwiki — an XWiki server (a powerful, self-hosted enterprise wiki and application-development
// platform: structured pages, macros, apps and fine-grained rights). A plain composable
// kurly.http workload on the official PostgreSQL/Tomcat image, backed by an external PostgreSQL,
// with its permanent directory on a PersistentVolume. Import it, point it at a database, and
// render with kurly.list:
//
//   local xwiki = import 'github.com/metio/kurly/workloads/xwiki/server.libsonnet';
//   kurly.list(xwiki())
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// DATABASE & SECRETS: XWiki reads its database connection (DB_HOST, DB_USER, DB_PASSWORD,
// DB_DATABASE) from the environment. kurly authors no Secret; provide one holding them, via
// envFrom. Pairs with a cnpg-cluster named xwiki-db.
//
// Single writer: the permanent directory lives on a ReadWriteOnce volume, so one replica,
// recreated. The bundled Tomcat runs as root.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='xwiki',
  image='docker.io/xwiki:16-postgres-tomcat',
  storageSize='10Gi',
  storageClass=null,
  secretName='xwiki-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/usr/local/xwiki', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
