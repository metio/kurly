// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// hypermind — a peer-to-peer deployment counter and ephemeral chat: every
// instance joins a Hyperswarm DHT, discovers the others running the same image
// and shows how many there are, with a chat that keeps nothing. A plain
// composable kurly.http workload with no database, no volume and no external
// service. Import it and render with kurly.list:
//
//   local hypermind = import 'github.com/metio/kurly/workloads/hypermind/server.libsonnet';
//   kurly.list(hypermind())
//
// Serves on :3000 — compose an exposure onto it.
//
// IT TALKS TO STRANGERS ON THE PUBLIC INTERNET, WHICH IS THE ENTIRE POINT. The
// pod dials out to a distributed hash table to find other instances, so a cluster
// with a default-deny egress policy gives it nothing to count, and a cluster
// without one lets it hold connections to peers nobody vetted. Both are correct
// outcomes for what this is; neither is a configuration mistake.
//
// NOTHING IS KEPT. Messages exist for as long as a peer is connected and the
// count is whoever answers right now, so there is no volume here and a restart
// starts over. Upstream calls it a toy, and the recipe treats it as one.
//
// Stateless: a plain rolling Deployment. Replicas are peers of each other rather
// than copies, so more of them means a larger count and not more capacity.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='hypermind',
  image=defaultImage,
  replicas=1,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env({ PORT: '3000' } + env)
  // The image runs node as root and owns nothing that needs it.
  + kurly.runAs(1000, gid=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
