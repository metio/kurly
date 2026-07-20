// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// homepage — a Homepage server (a modern, fully static, highly-configurable application
// dashboard with service/bookmark widgets and live status). A plain composable
// kurly.http workload on the official image; its YAML configuration lives on a
// PersistentVolume, so it needs no external database. Import it, adapt with the
// parameters below, and render with kurly.list:
//
//   local homepage = import 'github.com/metio/kurly/workloads/homepage/server.libsonnet';
//   kurly.list(homepage(allowedHosts='home.example.com'))
//
// Serves the dashboard on :3000 — compose an exposure onto it.
//
// ALLOWED HOSTS: recent Homepage releases refuse requests whose Host header is not in
// HOMEPAGE_ALLOWED_HOSTS, so set allowedHosts to the host you serve it on (a
// comma-separated list) or the page returns a host-validation error.
//
// Single writer: the configuration lives on a ReadWriteOnce volume, so one replica,
// recreated. Homepage reads its config on start; edit the files on the volume and
// restart, or drive it entirely from Kubernetes service discovery.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='homepage',
  image='ghcr.io/gethomepage/homepage:v1.13.2',
  storageSize='1Gi',
  storageClass=null,
  // The host(s) Homepage answers on (HOMEPAGE_ALLOWED_HOSTS, comma-separated).
  allowedHosts=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if allowedHosts == null then {} else { HOMEPAGE_ALLOWED_HOSTS: allowedHosts };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
