// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// formbricks — a Formbricks server (a self-hosted, open-source experience-management and
// survey platform: build in-product surveys and forms and analyse the responses). A plain
// composable kurly.http workload on the official image, backed by an external PostgreSQL.
// Import it, point it at a database, and render with kurly.list:
//
//   local formbricks = import 'github.com/metio/kurly/workloads/formbricks/server.libsonnet';
//   kurly.list(formbricks(webappUrl='https://surveys.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// DATABASE & SECRETS: Formbricks reads DATABASE_URL, NEXTAUTH_SECRET and ENCRYPTION_KEY from
// the environment. kurly authors no Secret; provide one holding them, via envFrom. The
// defaults pair with a cnpg-cluster named formbricks-db.
//
// Stateless: surveys and responses live in PostgreSQL, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='formbricks',
  image='ghcr.io/formbricks/formbricks:v2.6.0',
  replicas=2,
  webappUrl=null,
  secretName='formbricks-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if webappUrl == null then {} else { WEBAPP_URL: webappUrl, NEXTAUTH_URL: webappUrl };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
