// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// vinyl-cache — a caching HTTP reverse proxy: it sits in front of an application, keeps the
// responses it is allowed to keep in memory, and serves the next request for them itself. A
// plain composable kurly.http workload on the official image. Import it, point it at a
// backend, and render with kurly.list:
//
//   local vinyl = import 'github.com/metio/kurly/workloads/vinyl-cache/server.libsonnet';
//   kurly.list(vinyl(backendUrl='http://my-app.my-namespace.svc:8080'))
//
// Serves on :8080 — compose an exposure onto it.
//
// WITHOUT A BACKEND IT IS NOT A PROXY. The VCL the image ships answers every request from a
// static page baked into the image unless VARNISH_BACKEND_HOST names one, so a deployment
// that forgets `backendUrl` comes up healthy and caches nothing anybody asked for. The URL
// must carry a scheme: the shipped VCL refuses to load without one, which fails the whole
// startup rather than proxying somewhere unintended.
//
// CONFIG IS THE WORKLOAD: `vcl` is the Varnish Configuration Language, which kurly does not
// model — a second-hand copy would drift against the real grammar and lie about what it
// accepts — so it is mounted verbatim beside the image's own /etc/varnish and named through
// VARNISH_VCL_FILE. Beside, never over: the shipped hit-miss.vcl and verbose_builtin.vcl stay
// on the default include path, so a VCL that includes them still loads.
//
// THE CACHE IS MEMORY, and the two numbers must agree: `cacheSize` is handed to varnishd as
// its malloc store, and the container's memory limit has to leave room for it plus the
// process itself. Raising one without the other is how the cache gets the pod OOM-killed
// under exactly the load it was added for.
//
// Stateless: the cache is memory and starts cold, so the workload keeps nothing and scales
// horizontally — at the price of each replica holding its own copy of the cache.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='vinyl-cache',
  image=defaultImage,
  replicas=2,
  port=8080,
  backendUrl=null,
  cacheSize='128M',
  vcl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(80)
  + kurly.env(
    {
      // The entrypoint binds :80 unless told otherwise, which an unprivileged uid cannot
      // rely on; the listener is moved to the declared port instead.
      VARNISH_HTTP_PORT: std.toString(port),
      VARNISH_SIZE: cacheSize,
    }
    + (if backendUrl == null then {} else { VARNISH_BACKEND_HOST: backendUrl })
    + (if vcl == null then {} else { VARNISH_VCL_FILE: '/etc/varnish-vcl/default.vcl' })
    + env
  )
  // Mounted beside the image's own /etc/varnish, never over it: the includes the shipped
  // VCL uses resolve through varnishd's default vcl_path, which is that directory.
  + (if vcl == null then {} else kurly.config({ 'default.vcl': vcl }, mountPath='/etc/varnish-vcl'))
  // The image's own uid, which owns the working directory the packaging created.
  + kurly.runAs(1000, gid=1000)
  // varnishd keeps its shared memory log and the compiled VCLs under its working directory,
  // and exits at startup if it cannot write there.
  + kurly.scratch('/var/lib/varnish')
  // Probe by connection: which paths answer, and with what, is the backend's business — an
  // httpGet on '/' is whatever the cached application decided to return, 404 included.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
