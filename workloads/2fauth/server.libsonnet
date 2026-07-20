// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// 2fauth — a 2FAuth server (a self-hosted web app to manage your two-factor-authentication
// TOTP/HOTP accounts and generate one-time codes in one place). A plain composable
// kurly.http workload on the official image; with the default SQLite backend its database
// lives on a PersistentVolume. Import it, adapt with the parameters below, and render with
// kurly.list:
//
//   local twofauth = import 'github.com/metio/kurly/workloads/2fauth/server.libsonnet';
//   kurly.list(twofauth(appUrl='https://2fa.example.com'))
//
// Serves the web app on :8000 — compose an exposure onto it.
//
// SECRET: 2FAuth needs APP_KEY (the Laravel app key, which encrypts stored 2FA secrets).
// kurly authors no Secret; provide one holding it, pulled in via envFrom.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='2fauth',
  image='docker.io/2fauth/2fauth:5.6.0',
  storageSize='1Gi',
  storageClass=null,
  appUrl=null,
  secretName='2fauth-secrets',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if appUrl == null then {} else { APP_URL: appUrl };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/2fauth', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
