// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// thumbor — a thumbor server (an on-demand image service: crop, resize, filter and
// re-encode images from a URL). A plain composable kurly.http workload on the official
// image. Import it, configure it, and render with kurly.list:
//
//   local thumbor = import 'github.com/metio/kurly/workloads/thumbor/server.libsonnet';
//   kurly.list(thumbor())
//
// Serves on :8888 — compose an exposure onto it.
//
// CONFIGURATION: the container runs `thumbor --use-environment`, so every thumbor
// configuration key is set as an environment variable of the same name (STORAGE,
// LOADER, ALLOW_UNSAFE_URL, ALLOWED_SOURCES, …) through env or a Secret composed on
// with kurly.envFromSecret.
//
// SECURITY: thumbor ships a PUBLISHED default SECURITY_KEY and ALLOW_UNSAFE_URL=True,
// which together let anyone hand it any URL and have it fetched and re-served. Set
// SECURITY_KEY from a Secret and ALLOW_UNSAFE_URL=False, and restrict ALLOWED_SOURCES
// to the hosts whose images you serve.
//
// Stateless: the file storage cache lives in the scratch under /tmp (thumbor's own
// default location), so each replica keeps its own and the set scales horizontally.
// Point STORAGE at a shared backend if the cache has to be shared.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='thumbor',
  image=defaultImage,
  replicas=2,
  cacheSize='2Gi',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8888)
  + kurly.servicePort(8888)
  // Reads its whole configuration from the environment; without this flag the
  // variables below are ignored and the built-in defaults serve instead.
  // `--use-environment` TAKES A VALUE. thumbor's argument parser rejects the
  // bare flag ("expected one argument") and the container exits before it binds
  // a port, so the readiness probe reports a refused connection and the pod
  // reads as an unhealthy application rather than as a bad command line.
  + kurly.args(['--use-environment', 'True', '--log-level', 'info'])
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Decoding, encoding and the file-storage cache all write under the system
  // temporary directory, the only path it writes to.
  + kurly.scratch('/tmp', cacheSize)
  + kurly.readinessProbe({ httpGet: { path: '/healthcheck', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthcheck', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
