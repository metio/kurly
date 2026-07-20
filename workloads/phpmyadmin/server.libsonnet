// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// phpmyadmin — a phpMyAdmin server (the classic web UI for administering MySQL and MariaDB:
// browse databases, run SQL, manage users and import/export data). A plain composable
// kurly.http workload on the official image. It holds no state — it connects to the MySQL
// server you point it at — so it is a plain stateless Deployment. Import it and render with
// kurly.list:
//
//   local phpmyadmin = import 'github.com/metio/kurly/workloads/phpmyadmin/server.libsonnet';
//   kurly.list(phpmyadmin(dbHost='mysql'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// TARGET: point it at the MySQL/MariaDB host through PMA_HOST (dbHost below). Credentials
// are entered at the login screen, or set through the image's PMA_* environment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='phpmyadmin',
  image='docker.io/library/phpmyadmin:5.2.2',
  replicas=2,
  dbHost=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if dbHost == null then {} else { PMA_HOST: dbHost };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
