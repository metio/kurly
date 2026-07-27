// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// duplicati — a a Duplicati server (a self-hosted, encrypted backup client for cloud and remote storage, managed from the browser). A plain composable kurly.http workload on the LinuxServer.io
// image; its application config lives on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local duplicati = import 'github.com/metio/kurly/workloads/duplicati/server.libsonnet';
//   kurly.list(duplicati())
//
// Serves the web app on :8200 — compose an exposure onto it.
//
// LINUXSERVER IMAGE: the s6-overlay init runs as root and drops to the PUID/PGID user,
// so this runs as root with a writable root filesystem — kurly keeps the rest of the
// hardening (dropped capabilities, seccomp, no privilege escalation, resource limits).
// Set puid/pgid to own the mounted files.
//
// SECRETS: Duplicati refuses to start without SETTINGS_ENCRYPTION_KEY — the key it
// encrypts its settings database with. It reads that (and an optional
// DUPLICATI__WEBSERVICE_PASSWORD for the web UI) from the Secret named by
// secretName; kurly authors none.
//
// Single writer: the config lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='duplicati',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  secretName='duplicati',
  puid=1000,
  pgid=1000,
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8200)
  + kurly.servicePort(8200)
  + kurly.envFromSecret(secretName)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // The LinuxServer.io s6-overlay init starts as root and drops to PUID/PGID,
  // so it needs to gain privileges and keep the SETUID/SETGID capabilities.
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  // The s6 init unpacks and prepares the app before the web service binds.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
