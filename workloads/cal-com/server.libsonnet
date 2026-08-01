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
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='cal-com',
  image=defaultImage,
  // Cal.com applies its Prisma migrations on start, and two instances coming up
  // together race for them — so it starts single and is scaled once the schema is
  // in place.
  replicas=1,
  webappUrl=null,
  secretName='cal-com',
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
  // yarn rewrites its install state on start, inside the image's own .yarn
  // directory. That directory cannot be a scratch — it also holds `patches`,
  // `releases` and `versions`, 3.5MB the build needs, and an emptyDir would hide
  // all of it — so the one file that moves is pointed at the scratch instead, and
  // the root filesystem stays read-only.
  + kurly.env({ YARN_INSTALL_STATE_PATH: '/tmp/install-state.gz' } + baseEnv + env)
  // The image runs as root and owns its build tree, which yarn and Prisma write
  // into while the app boots.
  + kurly.rootUser()
  + kurly.scratch('/tmp', '128Mi')
  // The first start migrates the schema and seeds the app catalogue before the
  // server binds, which takes minutes.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 15, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
