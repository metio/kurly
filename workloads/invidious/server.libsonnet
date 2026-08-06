// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// invidious — an Invidious server (a privacy-preserving alternative front end for
// YouTube). A plain composable kurly.http workload on the official image, backed by
// an external PostgreSQL; it keeps no state of its own, so it claims no volume.
// Import it, point it at its database, and render with kurly.list:
//
//   local invidious = import 'github.com/metio/kurly/workloads/invidious/server.libsonnet';
//   kurly.list(invidious(domain='watch.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// CONFIGURATION: the image ships config/config.yml and overrides every key from an
// INVIDIOUS_<KEY> environment variable, so the whole configuration is env, no
// ConfigMap and no config document to author. kurly authors no Secret; provide one
// holding INVIDIOUS_DATABASE_URL and INVIDIOUS_HMAC_KEY, pulled in via envFrom. The
// default pairs with a cnpg-cluster named invidious-db.
//
// Service links are DISABLED deliberately: a Service named invidious makes Kubernetes
// inject INVIDIOUS_PORT as a tcp:// URL, which is exactly the name Invidious reads as
// its listen port, and the server then fails to bind.
//
// checkTables lets the server create and migrate its own schema on first start, which
// is what makes a fresh database usable without a separate migration job — and why the
// startup probe allows several minutes before the liveness probe takes over.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='invidious',
  image=defaultImage,
  // The public domain, used to build the URLs the pages link to. Null serves the
  // instance under whatever host reaches it.
  domain=null,
  // The port the public URLs carry — 443 behind TLS.
  externalPort=null,
  // Create and migrate the schema on start.
  checkTables=true,
  // The Secret holding INVIDIOUS_DATABASE_URL and INVIDIOUS_HMAC_KEY (kurly mints
  // none), via envFrom.
  secretName='invidious',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    (if domain == null then {} else { INVIDIOUS_DOMAIN: domain })
    + (if externalPort == null then {} else { INVIDIOUS_EXTERNAL_PORT: std.toString(externalPort) });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv {
    INVIDIOUS_HOST_BINDING: '0.0.0.0',
    INVIDIOUS_PORT: '3000',
    INVIDIOUS_CHECK_TABLES: if checkTables then 'true' else 'false',
  } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.disableServiceLinks()
  + kurly.scratch('/tmp', '64Mi')
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 45 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
