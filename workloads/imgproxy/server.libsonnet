// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// imgproxy — a fast and secure server for resizing, converting and processing
// images on the fly. A plain composable kurly.http workload: it keeps nothing,
// fetching each source image over HTTP (or from object storage) and streaming the
// result back, so it needs no PersistentVolume and any replica count is safe.
// Import it and render with kurly.list:
//
//   local imgproxy = import 'github.com/metio/kurly/workloads/imgproxy/server.libsonnet';
//   kurly.list(imgproxy())
//
// Serves on :8080 — compose an exposure onto it.
//
// SIGNATURES: an imgproxy reachable without a URL signature will process any URL
// anybody hands it, which is a bandwidth and SSRF liability rather than a feature.
// `secretName` points at a Secret holding IMGPROXY_KEY and IMGPROXY_SALT (both
// hex), which imgproxy then requires on every request. Left null the server
// accepts unsigned URLs, which suits a cluster-internal imgproxy behind something
// that already decides who may ask.
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
  name='imgproxy',
  image=defaultImage,
  replicas=2,
  // A Secret carrying IMGPROXY_KEY and IMGPROXY_SALT — the hex pair that makes
  // imgproxy demand a signature on every URL.
  secretName=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env({ IMGPROXY_BIND: ':8080' } + env)
  // The image's own unprivileged uid; nothing in it is owned by the user, so the
  // read-only root filesystem is enough.
  + kurly.runAs(999, gid=999)
  + kurly.scratch('/tmp', '64Mi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
