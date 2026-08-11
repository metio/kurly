// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// peer-calls — group video calls in the browser over WebRTC. A plain composable
// kurly.http workload: calls are peer-to-peer or relayed through the server's own
// SFU, and nothing is written down, so it needs no database and no
// PersistentVolume. Import it and render with kurly.list:
//
//   local peercalls = import 'github.com/metio/kurly/workloads/peer-calls/server.libsonnet';
//   kurly.list(peercalls())
//
// Serves the web app and the signalling WebSocket on :3000 — compose an exposure
// onto it. TLS is not optional in practice: a browser will not hand a page its
// camera or microphone unless the page came over HTTPS.
//
// REPLICAS: signalling state lives in the process, so two pods answering the same
// room do not see each other's peers and the call silently splits. One replica
// unless `redisHost` names a Redis for peer-calls to share that state through.
//
// Stateless: the process writes nothing outside /tmp, which is a scratch volume,
// so the root filesystem stays read-only.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='peer-calls',
  image=defaultImage,
  // Only raise this alongside redisUrl — see REPLICAS above.
  replicas=1,
  // The Redis peer-calls shares signalling state through.
  redisHost=null,
  redisPort=6379,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(
    { PEERCALLS_BIND_HOST: '0.0.0.0', PEERCALLS_BIND_PORT: '3000' }
    + (if redisHost != null then {
         PEERCALLS_STORE_TYPE: 'redis',
         PEERCALLS_STORE_REDIS_HOST: redisHost,
         PEERCALLS_STORE_REDIS_PORT: std.toString(redisPort),
         PEERCALLS_STORE_REDIS_PREFIX: 'peercalls',
       } else {})
    + env
  )
  // The image ships a single static binary and no user of its own; nothing in it
  // is owned by the runtime user, so any unprivileged uid serves.
  + kurly.runAs(65534, gid=65534)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
