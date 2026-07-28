// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// yourls — a YOURLS server (Your Own URL Shortener: a small, self-hosted PHP app for running
// your own short links with stats and a plugin system). A plain composable kurly.http workload
// on the official image, backed by an external MySQL/MariaDB. Import it, point it at a database,
// and render with kurly.list:
//
//   local yourls = import 'github.com/metio/kurly/workloads/yourls/server.libsonnet';
//   kurly.list(yourls(site='https://s.example.com'))
//
// Serves the web app and redirects on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: YOURLS reads YOURLS_DB_HOST, YOURLS_DB_USER, YOURLS_DB_PASS,
// YOURLS_DB_NAME and the admin YOURLS_USER/YOURLS_PASS from the environment. kurly authors no
// Secret; provide one holding them, via envFrom. Pairs with a mysql-cluster named yourls-db.
//
// Stateless: links live in MySQL, so this is a plain rolling Deployment. The Apache master runs
// as root then serves as www-data.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='yourls',
  image=defaultImage,
  replicas=2,
  site=null,
  secretName='yourls',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if site == null then {} else { YOURLS_SITE: site };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  // The image's Apache serves on :8080 as the unprivileged web user; the Service
  // keeps :80.
  + kurly.port(8080)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  // The entrypoint unpacks YOURLS onto the volume and hands it to the web user.
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  // An uninstalled YOURLS redirects into its installer, and the kubelet follows the
  // chain — so readiness is a connection check.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
