// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// glitchtip — a GlitchTip server (an open-source, Sentry-compatible error-tracking
// and performance-monitoring platform). This is the WEB front end, a kurly.http
// workload on the official image, backed by an external PostgreSQL and Redis. It
// needs the companion `worker` stage for background jobs. Import both and render with
// kurly.list:
//
//   local glitchtip = import 'github.com/metio/kurly/workloads/glitchtip/server.libsonnet';
//   kurly.list(glitchtip(domain='https://errors.example.com'))
//
// Serves the web app and the Sentry-compatible ingest API on :8080 — compose an
// exposure onto it. Being stateless (its state lives in the database), it can run
// several replicas.
//
// DATABASE, CACHE & SECRETS: GlitchTip reads DATABASE_URL (with the database password
// embedded) and SECRET_KEY from a provided Secret via envFrom, and REDIS_URL and its
// domain from env. The defaults pair with a cnpg-cluster named glitchtip-db and a
// valkey named glitchtip-cache. kurly authors no Secret.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='glitchtip',
  image='docker.io/glitchtip/glitchtip:v6.2.2',
  redisHost='glitchtip-cache',
  // The public URL GlitchTip serves at.
  domain=null,
  // The Secret holding DATABASE_URL and SECRET_KEY (kurly mints none), via envFrom.
  secretName='glitchtip-secrets',
  replicas=1,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    REDIS_URL: 'redis://' + redisHost + ':6379/0',
    PORT: '8080',
  } + (if domain == null then {} else { GLITCHTIP_DOMAIN: domain });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/_health/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/_health/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
