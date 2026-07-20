// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pocket-id — a Pocket ID server (a simple, self-hosted OIDC provider that lets people log in
// to your apps with passkeys — no passwords). A plain composable kurly.http workload on the
// official image; with the default SQLite backend its database and keys live on a
// PersistentVolume. Import it, adapt with the parameters below, and render with kurly.list:
//
//   local pocketId = import 'github.com/metio/kurly/workloads/pocket-id/server.libsonnet';
//   kurly.list(pocketId(appUrl='https://id.example.com'))
//
// Serves the web app and OIDC endpoints on :1411 — compose an exposure onto it.
//
// APP URL: Pocket ID publishes its issuer and callback URLs from APP_URL, and passkeys are
// bound to that origin, so set it to the public HTTPS URL you serve it on.
//
// Single writer: the SQLite database and keys live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='pocket-id',
  image='ghcr.io/pocket-id/pocket-id:v1.0.0',
  storageSize='1Gi',
  storageClass=null,
  appUrl=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if appUrl == null then {} else { APP_URL: appUrl, TRUST_PROXY: 'true' };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(1411)
  + kurly.servicePort(1411)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
