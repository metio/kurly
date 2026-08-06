// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// caddy — a Caddy server (a web server, static file server and reverse proxy with a config
// API). A plain composable kurly.http workload on the official image. Its whole behaviour is
// its Caddyfile, mounted as a ConfigMap and passed verbatim; it keeps no persistent state of
// its own here. Import it, pass your Caddyfile, and render with kurly.list:
//
//   local caddy = import 'github.com/metio/kurly/workloads/caddy/server.libsonnet';
//   kurly.list(caddy(caddyfile=|||
//     :8080 {
//       reverse_proxy backend:3000
//     }
//   |||))
//
// Serves on :8080 — compose an exposure onto it.
//
// CONFIG IS THE WORKLOAD: `caddyfile` is Caddy's own configuration language, which kurly
// does not model — a second-hand copy would drift against Caddy's and lie about what it
// accepts — so it is mounted verbatim. The default serves the image's own static site,
// which is what makes the stage bootable as it stands.
//
// NO AUTOMATIC HTTPS: the site address is a bare port, so Caddy serves plain HTTP and never
// asks for a certificate. TLS belongs to the exposure composed onto this workload (an
// Ingress or an HTTPRoute), which is where a cluster already terminates it, and it is why
// /data holds nothing worth keeping — a scratch is enough for the certificate store and the
// admin API's autosaved config, and the workload scales horizontally. A Caddyfile that asks
// for a public hostname instead wants a kurly.store at /data, so the issued certificates
// survive a restart and the ACME account is not re-registered on every roll.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

// A working default: serve the static site the image already ships, on the declared port.
local defaultCaddyfile = |||
  :8080 {
  	root * /usr/share/caddy
  	file_server
  }
|||;

function(
  name='caddy',
  image=defaultImage,
  replicas=2,
  caddyfile=defaultCaddyfile,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // The image reads /etc/caddy/Caddyfile and ships nothing else in that directory.
  + kurly.config({ Caddyfile: caddyfile }, mountPath='/etc/caddy')
  // The admin API autosaves the running config under XDG_CONFIG_HOME, which the image sets
  // to /config. It is pointed at the scratch below instead: a second volume mounted at
  // /config would be named after that path, colliding with the ConfigMap's own volume and
  // shadowing the Caddyfile — the container then starts and exits on a config file that is
  // not there.
  + kurly.env({ XDG_CONFIG_HOME: '/data/config' } + env)
  // The image declares root and the entrypoint drops nothing, so the user is pinned here.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The binary carries the file capability cap_net_bind_service, and a file with permitted
  // capabilities cannot be exec'd at all once the bounding set drops them: the kernel
  // refuses with `exec /usr/bin/caddy: operation not permitted`, which reads as a broken
  // image rather than a dropped capability. Everything else stays dropped, and granting it
  // back is also what lets a Caddyfile bind :80/:443 directly.
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  // XDG_DATA_HOME: the certificate store, Caddy's own state, and the autosaved config.
  + kurly.scratch('/data')
  // Probe by connection: which paths answer, and with what, is entirely the caller's
  // Caddyfile — an httpGet on '/' is a 404 the moment somebody deploys their own site.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
