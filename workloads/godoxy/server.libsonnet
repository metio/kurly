// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// godoxy — a GoDoxy server (a reverse proxy that routes to backends and issues
// certificates for them automatically). A plain composable kurly.http workload
// keeping its route configuration on a PersistentVolume. Import it and render
// with kurly.list:
//
//   local godoxy = import 'github.com/metio/kurly/workloads/godoxy/server.libsonnet';
//   kurly.list(godoxy())
//
// Serves the proxy entrypoint — which is also where the WebUI is answered, by
// hostname — on :8080; compose an exposure onto it.
//
// NO DOCKER: upstream's own deployment reads a Docker socket and discovers its
// routes from container labels. A pod has no such socket, so nothing is
// discovered here and the routes are the files under /app/config on the volume —
// written through the WebUI, or placed there beforehand. Neither DOCKER_HOST nor
// a socket-proxy sidecar is rendered: a route that names a Docker container
// cannot be reached from a Kubernetes Service anyway.
//
// TLS BELONGS TO THE EXPOSURE: GODOXY_HTTPS_ADDR is empty and HTTP/3 is off, so
// GoDoxy opens no TLS listener and never asks for a certificate — the cluster
// already terminates TLS in the Ingress or HTTPRoute composed onto this
// workload. Its own autocert wants a DNS-01 provider token and a wildcard record,
// which is a second certificate authority in a cluster that has one. Give it back
// by setting GODOXY_HTTPS_ADDR through env and adding kurly.extraPort.
//
// THE API PORT IS PUBLISHED (:8888), not left on the loopback address the image
// defaults to: a probe, a scrape and the WebUI's own browser all reach it from
// outside the pod's network namespace. It is authenticated — which is why the
// Secret below is a prerequisite rather than hardening.
//
// SECRET: GODOXY_API_USER and GODOXY_API_PASSWORD are REQUIRED unless OIDC is
// configured — GoDoxy exits with "GODOXY_API_USER and GODOXY_API_PASSWORD must be
// set" and the pod never starts. GODOXY_API_JWT_SECRET signs the session tokens;
// unset, a random key is minted per start, so every restart logs everybody out.
// kurly mints no Secret; the consumer provides it.
//
// PROBES ask the port, never a path: the proxy entrypoint answers with whatever a
// configured route names, or with a 404 for a host it does not know, and the API
// answers 401 until a session exists — none of which says GoDoxy is unhealthy.
//
// Single writer: one route configuration on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='godoxy',
  image=defaultImage,
  storageSize='1Gi',
  storageClass=null,
  // The Secret holding GODOXY_API_USER, GODOXY_API_PASSWORD and
  // GODOXY_API_JWT_SECRET. kurly mints no Secret; the consumer provides it.
  secretName='godoxy',
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // The REST API and the WebUI's own backend. The image binds it to 127.0.0.1,
  // which no probe and no browser outside the pod can reach.
  + kurly.extraPort('api', 8888)
  + kurly.env({
    // Unprivileged ports, so the hardened default keeps every capability dropped
    // instead of granting NET_BIND_SERVICE just to answer on :80.
    GODOXY_HTTP_ADDR: ':8080',
    GODOXY_HTTPS_ADDR: '',
    GODOXY_HTTP3_ENABLED: 'false',
    GODOXY_API_ADDR: ':8888',
    // The sensor collector reads host hardware a container does not see.
    GODOXY_METRICS_DISABLE_SENSORS: 'true',
  } + env)
  + kurly.envFromSecret(secretName)
  // A single static Go binary from a FROM-scratch image; the compose file upstream
  // ships pins the same uid and drops every capability, and nothing here needs one.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The binary is built with the file capability cap_net_bind_service, and a file
  // carrying permitted capabilities cannot be exec'd at all once the bounding set
  // drops them: the kernel refuses with `exec /app/run: operation not permitted`,
  // which reads as a broken image rather than a dropped capability. Everything
  // else stays dropped, and granting it back is also what lets the listen
  // addresses above be moved to :80 and :443.
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  // The Service is named after the workload, so Kubernetes would inject
  // GODOXY_PORT=tcp://… — the exact shape of a variable this application reads its
  // own configuration from. Nothing here needs the injected links.
  + kurly.disableServiceLinks()
  // config.yml, the route files and the middleware compose files. The server
  // creates config/middlewares itself at startup and the API writes here, so it
  // cannot be a read-only ConfigMap mount.
  + kurly.store('/app/config', storageSize, storageClass=storageClass)
  // Created at startup beside the config directory, and the read-only root
  // filesystem stays: the icon cache and the metrics series, the fallback error
  // pages, the certificate store autocert would use, and the access logs.
  + kurly.scratch('/app/data')
  + kurly.scratch('/app/error_pages')
  + kurly.scratch('/app/certs')
  + kurly.scratch('/app/logs')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
