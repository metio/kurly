// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// rss-bridge — an RSS-Bridge server (generates RSS/Atom feeds for sites that do not
// publish their own, from a large library of community "bridges"). A plain composable
// kurly.http workload on the official image. It holds no persistent state — feeds are
// produced on request — so it is a plain stateless Deployment. Import it and render with
// kurly.list:
//
//   local rssBridge = import 'github.com/metio/kurly/workloads/rss-bridge/server.libsonnet';
//   kurly.list(rssBridge())
//
// Serves the web app and feed endpoints on :80 — compose an exposure onto it.
//
// To restrict which bridges are enabled, mount a whitelist.txt over
// /app/whitelist.txt (a secretMount or config volume composed on).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='rss-bridge',
  image='docker.io/rssbridge/rss-bridge:2025-08-05',
  replicas=2,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(env)
  // The Apache master runs as root then serves as www-data; the root filesystem stays
  // writable for Apache's runtime state.
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
