// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// overleaf — an Overleaf server (the Community Edition of the collaborative LaTeX
// editor, formerly ShareLaTeX). A plain composable kurly.http workload on the
// official monolith image, backed by an external MongoDB and Redis, with its user
// projects and compiles on a PersistentVolume. Import it, point it at the
// databases, and render with kurly.list:
//
//   local overleaf = import 'github.com/metio/kurly/workloads/overleaf/server.libsonnet';
//   kurly.list(overleaf(siteUrl='https://latex.example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASES & SECRETS: Overleaf needs MongoDB (a REPLICA SET — it uses
// transactions) and Redis. kurly ships neither MongoDB recipe; bring your own
// (Redis can be the valkey workload). It reads OVERLEAF_REDIS_HOST and its site
// config from env, and OVERLEAF_MONGO_URL (with any credentials) from a provided
// Secret via envFrom. kurly authors no Secret.
//
// The image spawns TeX compile processes and writes across the root filesystem, so
// this relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
// capabilities and no privilege escalation.
//
// Single writer: user projects and compiles live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='overleaf',
  image='docker.io/sharelatex/sharelatex:6.2.1',
  storageSize='10Gi',
  storageClass=null,
  redisHost='overleaf-cache',
  // The public URL Overleaf builds links against.
  siteUrl=null,
  appName='Overleaf',
  // The Secret holding OVERLEAF_MONGO_URL (kurly mints none), via envFrom.
  secretName='overleaf-secrets',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    OVERLEAF_REDIS_HOST: redisHost,
    REDIS_HOST: redisHost,
    OVERLEAF_APP_NAME: appName,
  } + (if siteUrl == null then {} else { OVERLEAF_SITE_URL: siteUrl });

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
  + kurly.store('/var/lib/overleaf', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/status', port: 'http' }, initialDelaySeconds: 30, periodSeconds: 15, failureThreshold: 20 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 60, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
