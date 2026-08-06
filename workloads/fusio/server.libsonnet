// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// fusio — a Fusio server (an API management platform for building and documenting
// HTTP APIs) on the official Apache/PHP image, backed by an external MySQL/MariaDB
// or PostgreSQL. Import it, point it at a database, and render with kurly.list:
//
//   local fusio = import 'github.com/metio/kurly/workloads/fusio/server.libsonnet';
//   kurly.list(fusio(appUrl='https://api.example.com'))
//
// Serves the API and backend on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: Fusio needs a MySQL/MariaDB or PostgreSQL database — the
// mysql-cluster and cnpg-cluster workloads provide one. It reads the whole
// connection as a Doctrine DSN in FUSIO_CONNECTION, plus FUSIO_PROJECT_KEY and the
// initial backend password FUSIO_BACKEND_PW, from a provided Secret via envFrom.
// kurly authors no Secret.
//
// The entrypoint waits for the database, migrates the schema, creates the initial
// backend user and starts cron, supervisor and Apache as root, so this relaxes
// kurly's non-root and read-only-rootfs defaults while keeping dropped
// capabilities and no privilege escalation. That first run takes minutes, so it
// has a startup probe rather than a long liveness delay.
//
// Stateless: everything Fusio keeps lives in the database, so it claims no volume
// and scales horizontally.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='fusio',
  image=defaultImage,
  replicas=1,
  // The public URL Fusio builds links against, and where it serves its apps.
  appUrl=null,
  appsUrl=null,
  // The initial backend user created on first start (its password is in the Secret).
  backendUser='admin',
  backendEmail='admin@example.com',
  // The Secret holding FUSIO_CONNECTION, FUSIO_PROJECT_KEY and FUSIO_BACKEND_PW
  // (kurly mints none), via envFrom.
  secretName='fusio',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '768Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
                    FUSIO_ENV: 'prod',
                    FUSIO_DEBUG: 'false',
                    FUSIO_BACKEND_USER: backendUser,
                    FUSIO_BACKEND_EMAIL: backendEmail,
                  }
                  + (if appUrl == null then {} else { FUSIO_URL: appUrl })
                  + (if appsUrl == null then {} else { FUSIO_APPS_URL: appsUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  // A Service named after the workload makes Kubernetes inject FUSIO_PORT as a
  // tcp:// URL, and the entrypoint copies every FUSIO_* variable into the
  // environment Apache serves with.
  + kurly.disableServiceLinks()
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // Everything is dropped and these are granted back by name — Apache binds :80
  // and drops to www-data, and the entrypoint chowns the cache and log trees.
  + kurly.addCapabilities(['CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'FSETID', 'KILL', 'NET_BIND_SERVICE', 'SETGID', 'SETUID'])
  // The first start migrates the schema and creates the backend user before
  // Apache listens at all.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
