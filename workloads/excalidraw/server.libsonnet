// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// excalidraw — an Excalidraw server (a virtual hand-drawn-style whiteboard). A
// plain composable kurly.http workload on the official image. Excalidraw is a
// client-side app: the container just serves the static assets, and drawings live
// in the browser (or in a separate collaboration/storage backend), so this workload
// is stateless and can run several replicas. Import it and render with kurly.list:
//
//   local excalidraw = import 'github.com/metio/kurly/workloads/excalidraw/server.libsonnet';
//   kurly.list(excalidraw())
//
// Serves the app on :80 — compose an exposure onto it.
//
// The nginx image serving the static assets starts as root and binds :80, so this
// relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
// capabilities and no privilege escalation.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='excalidraw',
  // Excalidraw publishes no semver tags; this is the immutable sha tag (pinned,
  // reproducible), which Renovate tracks.
  image='docker.io/excalidraw/excalidraw:sha-4bfc5bb',
  replicas=1,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
