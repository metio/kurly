// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cal-com — a Cal.com server (a self-hosted, open-source scheduling platform, an alternative to
// Calendly). A plain composable kurly.http workload on the official image, backed by an external
// PostgreSQL. Import it, point it at its backends, and render with kurly.list:
//
//   local calcom = import 'github.com/metio/kurly/workloads/cal-com/server.libsonnet';
//   kurly.list(calcom(webappUrl='https://cal.example.com'))
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Cal.com reads DATABASE_URL, NEXTAUTH_SECRET, CALENDSO_ENCRYPTION_KEY,
// NEXT_PUBLIC_WEBAPP_URL and its integration credentials from the environment. kurly authors no
// Secret; provide one holding them, via envFrom. The defaults pair with a cnpg-cluster named
// cal-com-db.
//
// Stateless: a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='cal-com',
  image='docker.io/calcom/cal.com:latest@sha256:ace3bb1219fb7306585ab9f4d94d41af7ee064c343db0498173436bbe857bd49',
  replicas=2,
  webappUrl=null,
  secretName='cal-com-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if webappUrl == null then {} else { NEXT_PUBLIC_WEBAPP_URL: webappUrl, NEXTAUTH_URL: webappUrl };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
