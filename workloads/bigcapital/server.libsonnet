// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// bigcapital-server — the Bigcapital API/back end (Bigcapital is a self-hosted
// accounting and financial-management platform). A kurly.http workload on the
// official image, backed by external MySQL/MariaDB, MongoDB, and Redis. It is one
// of three coordinated stages — server, webapp, and gateway (the entry). Run all
// three pointed at the same namePrefix and secretName, plus the databases. See the
// workload README.
//
//   local server = import 'github.com/metio/kurly/workloads/bigcapital/server.libsonnet';
//   kurly.list(server())
//
// Serves the API on :4000; the gateway proxies to it.
//
// DATABASES & SECRETS: Bigcapital needs MySQL/MariaDB (system and tenant data),
// MongoDB, and Redis — kurly ships none of these MySQL/MongoDB recipes; bring your
// own (Redis can be the valkey workload). The non-secret coordinates come from env;
// the passwords and JWT secret come from a provided Secret via envFrom. kurly
// authors no Secret.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  namePrefix='bigcapital',
  name=null,
  image='docker.io/bigcapitalhq/server:v0.25.23',
  dbHost='bigcapital-mariadb',
  dbUser='bigcapital',
  mongoHost='bigcapital-mongo',
  redisHost='bigcapital-cache',
  // The public base URL of the deployment.
  baseUrl=null,
  // The Secret holding SYSTEM_DB_PASSWORD, TENANT_DB_PASSWORD, and JWT_SECRET
  // (kurly mints none), via envFrom.
  secretName='bigcapital-secrets',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-server';
  local baseEnv = {
    NODE_ENV: 'production',
    SYSTEM_DB_HOST: dbHost,
    SYSTEM_DB_PORT: '3306',
    SYSTEM_DB_USER: dbUser,
    SYSTEM_DB_NAME: 'bigcapital_system',
    TENANT_DB_HOST: dbHost,
    TENANT_DB_PORT: '3306',
    TENANT_DB_USER: dbUser,
    TENANT_DB_NAME_PREFIX: 'bigcapital_tenant_',
    MONGODB_DATABASE_URL: 'mongodb://' + mongoHost + ':27017/bigcapital',
    REDIS_HOST: redisHost,
    REDIS_PORT: '6379',
  } + (if baseUrl == null then {} else { BASE_URL: baseUrl });

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(4000)
  + kurly.servicePort(4000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
