// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// webtrees — a webtrees server (a self-hosted, collaborative online genealogy application:
// build and browse family trees, with charts, reports and media). A plain composable
// kurly.http workload on the community image, backed by an external MySQL/MariaDB, with its
// data (media, config) on a PersistentVolume. Import it, point it at a database, and render
// with kurly.list:
//
//   local webtrees = import 'github.com/metio/kurly/workloads/webtrees/server.libsonnet';
//   kurly.list(webtrees(baseUrl='https://tree.example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: webtrees reads its database connection (DB_HOST, DB_NAME, DB_USER,
// DB_PASS) and the install BASE_URL from the environment. kurly authors no Secret; provide
// one holding the DB credentials, via envFrom. Pairs with a mysql-cluster named webtrees-db.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated. The
// bundled Apache master runs as root then serves as www-data.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='webtrees',
  image='ghcr.io/nathanvaughn/webtrees:2.2.1',
  storageSize='10Gi',
  storageClass=null,
  baseUrl=null,
  secretName='webtrees-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { DB_TYPE: 'mysql', PRETTY_URLS: 'TRUE' }
    + (if baseUrl == null then {} else { BASE_URL: baseUrl });
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/webtrees/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
