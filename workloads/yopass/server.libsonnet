// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// yopass — a Yopass server (share a secret through a one-time, self-destructing
// encrypted link; the browser encrypts and decrypts, the server only ever holds
// ciphertext until it is read once or expires). A plain composable kurly.http
// workload on the official image, backed by an external Redis. Import it and
// render with kurly.list:
//
//   local yopass = import 'github.com/metio/kurly/workloads/yopass/server.libsonnet';
//   kurly.list(yopass())
//
// Serves the app and its API on :1337 — compose an exposure onto it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='yopass',
  image=defaultImage,
  replicas=2,
  redisHost='yopass-cache',
  redisPort=6379,
  redisDatabase=0,
  maxLength=10000,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(1337)
  + kurly.servicePort(1337)
  // Every setting is a flag — the binary reads no environment at all — so the
  // backend is selected here rather than left at the built-in memcached default.
  // Secrets live only in Redis, so the pod itself keeps no state and scales out.
  + kurly.args([
    '--database=redis',
    '--redis=redis://%s:%d/%d' % [redisHost, redisPort, redisDatabase],
    '--address=0.0.0.0',
    '--port=1337',
    '--max-length=%d' % maxLength,
  ])
  + kurly.env(env)
  // A distroless image with no declared user: the binary and the static assets
  // beside it are world-readable, and it writes nothing, so it runs as an
  // ordinary uid over a read-only root filesystem.
  + kurly.runAs(1000, gid=1000)
  // The bundled single-page app is served from the same port, so a plain GET on
  // / answers 200 without a redirect or an authentication challenge.
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
