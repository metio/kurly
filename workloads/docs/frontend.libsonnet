// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docs/frontend — the Next.js application Docs serves to a browser, behind nginx.
// A plain composable kurly.http workload holding nothing. Import it and render
// alongside the backend and y-provider.
//
// Serves the application on :8080 — compose an exposure onto it. THIS is the
// stage a user reaches; the backend and y-provider are spoken to from the browser
// through the same origin, so the exposure in front has to route /api and
// /collaboration to them.
//
// Stateless: nginx serves a built bundle, so any replica count is safe and there
// is no volume.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './frontend.image', '\n');

function(
  name='docs-frontend',
  image=defaultImage,
  replicas=2,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  // The uid and gid the image already runs as.
  + kurly.runAs(1001, gid=127)
  // nginx writes its temporary bodies and pid under these, which are inside the
  // read-only image.
  + kurly.scratch('/tmp', '128Mi')
  + kurly.scratch('/var/cache/nginx', '128Mi')
  + kurly.scratch('/var/run', '8Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
