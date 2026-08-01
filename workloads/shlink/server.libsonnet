// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// shlink — a Shlink server (a self-hosted URL shortener with a REST API and rich
// analytics). A plain composable kurly.http workload on the official image, backed by
// an external PostgreSQL. Import it, point it at a database, and render with
// kurly.list:
//
//   local shlink = import 'github.com/metio/kurly/workloads/shlink/server.libsonnet';
//   kurly.list(shlink(defaultDomain='s.example.com'))
//
// Serves the short-URL routes and REST API on :8080 — compose an exposure onto it.
// Being stateless (its state lives in the database), it can run several replicas.
//
// DATABASE & SECRETS: Shlink reads its database coordinates from env and DB_PASSWORD
// and the GEOLITE_LICENSE_KEY from the environment. The non-secret coordinates default
// to a cnpg-cluster named shlink-db; the secrets come from a provided Secret via
// envFrom. kurly authors no Secret.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='shlink',
  image=defaultImage,
  dbHost='shlink-db-rw',
  dbName='shlink',
  dbUser='shlink',
  // The default domain short URLs are generated under (required).
  defaultDomain=null,
  // The Secret holding DB_PASSWORD (and optionally GEOLITE_LICENSE_KEY), via envFrom.
  secretName='shlink',
  replicas=1,
  env={},
  // RoadRunner's WEB_WORKER_NUM defaults to 0, meaning one PHP worker per visible
  // CPU, so the http plugin's footprint scales with the node rather than with the
  // load. At a 512Mi limit the walk recorded an OOMKill on a 16-core node — which
  // is why rpc and jobs started and the http plugin alone never did.
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_DRIVER: 'postgres',
    DB_HOST: dbHost,
    DB_PORT: '5432',
    DB_NAME: dbName,
    DB_USER: dbUser,
    IS_HTTPS_ENABLED: 'true',
  } + (if defaultDomain == null then {} else { DEFAULT_DOMAIN: defaultDomain });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  // The image's own account owns the data directory Shlink generates its proxies in.
  + kurly.runAs(1001, gid=0, fsGroup=0)
  + kurly.scratch('/tmp', '64Mi')
  // Shlink generates its Doctrine proxies and caches beside its configuration on
  // every start, which the read-only root filesystem does not allow.
  + kurly.scratch('/etc/shlink/data/proxies', '32Mi')
  + kurly.scratch('/etc/shlink/data/cache', '64Mi')
  + kurly.scratch('/etc/shlink/data/log', '64Mi')
  + kurly.scratch('/etc/shlink/data/locks', '8Mi')
  // The first start migrates its schema, generates proxies and fetches the GeoLite
  // database before the API answers.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 45 })
  + kurly.readinessProbe({ httpGet: { path: '/rest/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/rest/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
