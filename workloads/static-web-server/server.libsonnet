// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// static-web-server — a Static Web Server (a small, fast asynchronous web server that
// serves a directory of static files). A plain composable kurly.http workload on the
// official image. It serves files and keeps no state, so it is a plain stateless
// Deployment. Import it and render with kurly.list:
//
//   local sws = import 'github.com/metio/kurly/workloads/static-web-server/server.libsonnet';
//   kurly.list(sws())
//
// Serves on :8080 — compose an exposure onto it, and mount the content to serve at
// `root` (a kurly.store, a configMount, or an image carrying its own files).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='static-web-server',
  image=defaultImage,
  replicas=2,
  // The image serves /public, which carries a placeholder page — enough to boot,
  // and the path a consumer mounts their own content over.
  root='/public',
  port=8080,
  env={},
  resources={ requests: { cpu: '50m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  // The image defaults to :80, which an unprivileged user cannot bind; SERVER_PORT
  // moves it, and the declared port follows it rather than the image's EXPOSE.
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.env({
    SERVER_PORT: std.toString(port),
    SERVER_ROOT: root,
  } + env)
  // A scratch image with a single static binary: no home, no state, nothing to own.
  + kurly.runAs(65532, gid=65532)
  // Every configuration knob is read from a SERVER_* variable, and a Service named
  // `server` would have Kubernetes inject SERVER_PORT as a tcp:// URL over the one
  // set above — the listen port then fails to parse and the container never starts.
  + kurly.disableServiceLinks()
  // Probed by connection: the content is the consumer's, so no path is guaranteed
  // to answer 200 — a directory without an index answers 404 and would kill the pod.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
