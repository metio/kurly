// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// activepieces — an Activepieces server (a self-hosted, open-source no-code automation
// / workflow builder, à la Zapier). A plain composable kurly.http workload on the
// official all-in-one image, backed by an external PostgreSQL and Redis. Import it,
// point it at its backends, and render with kurly.list:
//
//   local activepieces = import 'github.com/metio/kurly/workloads/activepieces/server.libsonnet';
//   kurly.list(activepieces(frontendUrl='https://flows.example.com'))
//
// Serves the web app and API on :80 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Activepieces reads its PostgreSQL and Redis connection, plus
// AP_ENCRYPTION_KEY and AP_JWT_SECRET, from the environment. kurly authors no Secret;
// provide one holding them (AP_POSTGRES_*, AP_REDIS_*, AP_ENCRYPTION_KEY, AP_JWT_SECRET),
// pulled in via envFrom. The defaults pair with a cnpg-cluster named activepieces-db and
// a Redis.
//
// Stateless: flow state lives in PostgreSQL and Redis, not on a volume, so this is a
// plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='activepieces',
  image='docker.io/activepieces/activepieces:0.86.3',
  replicas=2,
  // The public URL (Activepieces builds absolute links and webhook URLs from it).
  frontendUrl=null,
  // The Secret holding AP_POSTGRES_*, AP_REDIS_*, AP_ENCRYPTION_KEY and AP_JWT_SECRET
  // (kurly mints none), via envFrom.
  secretName='activepieces-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { AP_QUEUE_MODE: 'REDIS', AP_EXECUTION_MODE: 'UNSANDBOXED' }
    + (if frontendUrl == null then {} else { AP_FRONTEND_URL: frontendUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '256Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
