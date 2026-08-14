// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// varnish — an HTTP cache in front of something slower: it holds responses in
// memory and serves them without waking the backend, with the caching policy
// written in VCL. A plain composable kurly.http workload holding no state that
// outlives the pod. Import it and render with kurly.list:
//
//   local varnish = import 'github.com/metio/kurly/workloads/varnish/cache.libsonnet';
//   kurly.list(varnish(backendHost='app', backendPort=8080))
//
// Serves cached traffic on :80 — compose an exposure onto it and point it at the
// Service of whatever it is caching.
//
// THE CACHE IS MEMORY AND MEMORY IS A LIMIT, NOT A SUGGESTION. `size` is what
// Varnish is told it may use for objects, and the pod's memory limit has to be
// comfortably larger — the process needs room for its own working set on top, and
// a cache sized at the limit is a pod the kernel kills under load rather than one
// that evicts. The default here is deliberately small.
//
// VCL IS THE CONFIGURATION AND THIS RENDERS A DEFAULT ONE. `vcl` replaces it
// wholesale for anything past "cache what the backend says is cacheable" — there
// is no half-way merge of somebody else's caching policy.
//
// RESTARTING IT EMPTIES IT. Nothing is persisted, by design: the volume a cache
// would want is the memory it already has. A rollout is therefore a cold cache and
// a burst of traffic straight to the backend, which is worth knowing before
// rolling it during a peak.
//
// Stateless: a plain rolling Deployment, and replicas do not share a cache — each
// one fills its own.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './cache.image', '\n');

function(
  name='varnish',
  image=defaultImage,
  replicas=1,
  // The Service this caches for, and its port.
  backendHost='backend',
  backendPort=80,
  // What Varnish may use for cached objects. Keep the pod's memory limit above it.
  size='100M',
  // The whole VCL. Given, it replaces the default below entirely.
  vcl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local defaultVcl = |||
    vcl 4.1;

    backend default {
        .host = "%s";
        .port = "%s";
    }
  ||| % [backendHost, std.toString(backendPort)];

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env({ VARNISH_SIZE: size } + env)
  + kurly.config(
    { 'default.vcl': if vcl != null then vcl else defaultVcl },
    mountPath='/etc/varnish',
    subPath=true
  )
  // The uid the image's own varnish user carries.
  + kurly.runAs(1000, gid=1000)
  // The cache itself is memory, and the child process writes its shared-memory
  // log under /var/lib/varnish.
  + kurly.scratch('/var/lib/varnish', '256Mi')
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
