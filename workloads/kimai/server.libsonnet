// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kimai — a Kimai server (a self-hosted, professional time-tracking application for
// freelancers and teams: projects, activities, timesheets, invoicing and reports). A plain
// composable kurly.http workload on the official Apache image, backed by an external MySQL/
// MariaDB. Import it, point it at a database, and render with kurly.list:
//
//   local kimai = import 'github.com/metio/kurly/workloads/kimai/server.libsonnet';
//   kurly.list(kimai())
//
// Serves the web app on :8001 — compose an exposure onto it.
//
// DATABASE & SECRETS: Kimai reads DATABASE_URL and APP_SECRET from the environment. kurly
// authors no Secret; provide one holding them, pulled in via envFrom. Pairs with a
// mysql-cluster named kimai-db.
//
// Stateless: timesheets live in MySQL, so this is a plain rolling Deployment. The Apache
// master runs as root then serves as www-data.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='kimai',
  image='docker.io/kimai/kimai2:apache-2.38.0',
  replicas=2,
  secretName='kimai-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8001)
  + kurly.servicePort(8001)
  + kurly.envFromSecret(secretName)
  + kurly.env({ APP_ENV: 'prod' } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
