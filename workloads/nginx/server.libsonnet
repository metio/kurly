// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// nginx — an nginx server (the HTTP server and reverse proxy) on the official image. A plain
// composable kurly.http workload: it serves whatever its web root holds and keeps no state, so
// it is a plain stateless Deployment. Import it and render with kurly.list:
//
//   local nginx = import 'github.com/metio/kurly/workloads/nginx/server.libsonnet';
//   kurly.list(nginx())
//
// Serves on :8080 — compose an exposure onto it.
//
// CONFIGURATION: the image's own server block listens on :80, which an unprivileged process
// cannot bind, so the stage mounts its own server block into /etc/nginx/conf.d (a subPath
// mount, leaving the directory the image populates intact) listening on the port below. Pass
// `serverConfig` to replace that block outright — a reverse proxy, a different web root,
// caching — kurly does not model nginx's configuration language.
//
// CONTENT: the image's default web root (/usr/share/nginx/html) ships nginx's welcome page.
// Serve your own by composing a volume or a ConfigMap onto the workload at that path.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='nginx',
  image=defaultImage,
  replicas=2,
  port=8080,
  root='/usr/share/nginx/html',
  serverConfig=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  // One listen directive, IPv4 only: a second `listen [::]:…` aborts the whole
  // server on a single-stack cluster, which is most of them.
  local defaultServer = |||
    server {
        listen       %(port)d;
        server_name  _;

        location / {
            root   %(root)s;
            index  index.html index.htm;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   /usr/share/nginx/html;
        }
    }
  ||| % { port: port, root: root };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(80)
  // One server block dropped beside the directory the image populates, not over it.
  + kurly.config(
    { 'default.conf': if serverConfig == null then defaultServer else serverConfig },
    mountPath='/etc/nginx/conf.d',
    subPath=true,
  )
  + kurly.env(env)
  // The image declares root and its entrypoint would then chown its cache: as an
  // ordinary uid those steps skip themselves, and the packaged nginx user (101)
  // already owns what the server reads.
  + kurly.runAs(101, gid=101, fsGroup=101)
  // Writes its proxy and fastcgi caches under /var/cache/nginx; a scratch there
  // keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/cache/nginx')
  // Writes its pid file under /var/run.
  + kurly.scratch('/var/run')
  // Writes request bodies and the entrypoint's rendered templates under /tmp.
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
