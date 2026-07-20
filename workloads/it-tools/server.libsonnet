// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// it-tools — an IT-Tools server (a large collection of handy online tools for developers
// and sysadmins: encoders, converters, generators, formatters and more, all client-side).
// A plain composable kurly.http workload on the official image. It serves a static app
// and keeps no state, so it is a plain stateless Deployment. Import it and render with
// kurly.list:
//
//   local itTools = import 'github.com/metio/kurly/workloads/it-tools/server.libsonnet';
//   kurly.list(itTools())
//
// Serves the app on :80 — compose an exposure onto it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='it-tools',
  image='ghcr.io/corentinth/it-tools:2024.10.22-7ca5933',
  replicas=2,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(env)
  // The bundled nginx serves on :80 as the root master, then workers drop privileges;
  // the root filesystem stays writable for nginx's runtime state.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
