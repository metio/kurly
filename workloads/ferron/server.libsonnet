// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ferron — a Ferron web server (a fast, memory-safe HTTP server written in Rust,
// configured in KDL). A plain composable kurly.http workload: it serves files and
// keeps no state of its own, so it is a stateless Deployment with no volume and no
// Secret. Import it and render with kurly.list:
//
//   local ferron = import 'github.com/metio/kurly/workloads/ferron/server.libsonnet';
//   kurly.list(ferron())
//
// Serves on :8080 — compose an exposure onto it.
//
// The site it serves out of the box is the image's own placeholder page. To serve
// your own content, mount it and point `root` at the mount: a kurly.store for
// content that outlives the pod, a kurly.config for a handful of files, or an
// image of your own passed as `image`. Anything the KDL grammar expresses that
// these parameters do not can be passed as `config` verbatim.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='ferron',
  image=defaultImage,
  replicas=2,
  // The image's own config listens on :80, which an unprivileged process may not
  // bind. Rather than grant CAP_NET_BIND_SERVICE for one port, this stage writes
  // its own configuration on an unprivileged port and keeps every capability
  // dropped.
  port=8080,
  // The directory served. The image ships its placeholder site here.
  root='/var/www/ferron',
  // The whole KDL configuration, verbatim. Null renders the one below from `port`
  // and `root`; a string replaces it entirely, in which case `port` still governs
  // the container and Service ports and must match what the configuration binds.
  config=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  // The image's shipped configuration writes an access and an error log under
  // /var/log/ferron; leaving both out logs to stdout, which is where a cluster
  // reads them, and leaves the root filesystem read-only with no scratch.
  local kdl = if config != null then config else ':%d {\n  root "%s"\n}\n' % [port, root];

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.config({ 'ferron.kdl': kdl }, mountPath='/etc/ferron')
  // The image has no entrypoint — its CMD is the whole command — so pointing the
  // server at the mounted configuration overrides the command rather than
  // appending an argument, which would otherwise be run as the command itself.
  + kurly.command(['/usr/sbin/ferron', '-c', '/etc/ferron/ferron.kdl'])
  // The image sets `USER nobody` by NAME, which the kubelet cannot verify against
  // runAsNonRoot; pin the numeric uid so the restricted posture admits it.
  + kurly.runAs(65534)
  + (if env == {} then {} else kurly.env(env))
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
