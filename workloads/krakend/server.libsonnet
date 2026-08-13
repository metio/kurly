// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// krakend — a stateless API gateway that composes several backend calls into one
// endpoint and applies rate limiting, authentication and response filtering along
// the way. A plain composable kurly.http workload: the whole gateway is its
// configuration, rendered as a ConfigMap, so it keeps nothing and any replica
// count is safe. Import it and render with kurly.list:
//
//   local krakend = import 'github.com/metio/kurly/workloads/krakend/server.libsonnet';
//   kurly.list(krakend(endpoints=[{
//     endpoint: '/catalogue',
//     backend: [{ url_pattern: '/products', host: ['http://catalogue:8080'] }],
//   }]))
//
// Serves on :8080 — compose an exposure onto it.
//
// THE CONFIGURATION IS READ ONCE, AT STARTUP. KrakenD compiles its routes when
// the process starts and never re-reads the file, so changing the ConfigMap does
// nothing until the pods restart. Roll the Deployment after a change, or nothing
// visible happens and the old routes keep serving.
//
// Stateless: nothing is written outside /tmp, which is a scratch volume, so the
// root filesystem stays read-only and replicas scale freely.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='krakend',
  image=defaultImage,
  replicas=2,
  // KrakenD endpoint definitions, verbatim — the `endpoints` array of its
  // configuration file.
  endpoints=[],
  // How long the gateway waits on a backend before giving up.
  timeout='3s',
  // Merged over the rendered krakend.json — any of KrakenD's other settings,
  // including extra_config for the middleware it ships.
  config={},
  env={},
  resources={ requests: { cpu: '100m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  // The image runs as root by default; the gateway reads its configuration and
  // writes nothing, so an unprivileged uid serves.
  + kurly.runAs(1000, gid=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.config({
    'krakend.json': std.manifestJsonEx({
      '$schema': 'https://www.krakend.io/schema/v2.9/krakend.json',
      version: 3,
      name: name,
      port: 8080,
      timeout: timeout,
      endpoints: endpoints,
    } + config, '  '),
  }, mountPath='/etc/krakend')
  // A Service named after the workload makes Kubernetes inject KRAKEND_PORT as
  // a tcp:// URL, and KrakenD reads that variable as its listen port: it fails to
  // parse the URL as an integer and refuses to start.
  + kurly.disableServiceLinks()
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
