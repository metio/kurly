// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mainsail — a Mainsail server (the popular web interface for managing and controlling
// Klipper-based 3D printers). A plain composable kurly.http workload on the official
// unprivileged image. Mainsail is a browser app: it talks to a Moonraker API on the printer
// directly from the browser, so this workload only serves static assets and holds no state —
// a plain, horizontally scalable Deployment. Import it and render with kurly.list:
//
//   local mainsail = import 'github.com/metio/kurly/workloads/mainsail/server.libsonnet';
//   kurly.list(mainsail(moonrakerHost='printer.example.com'))
//
// Serves the app on :8080 — compose an exposure onto it.
//
// PRINTERS: moonrakerHost/moonrakerPort write the config.json Mainsail reads on load, so the
// browser connects to a printer without anybody typing an address. Both absent emits no
// ConfigMap and Mainsail asks for the address in the browser instead — which is the right
// default, since where a printer sits is not kurly's to assume. Pass `config` to override or
// extend the rest of that file verbatim (kurly does not model Mainsail's schema). The browser,
// not this pod, reaches Moonraker: the address has to be one the browser can resolve.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='mainsail',
  image=defaultImage,
  replicas=2,
  moonrakerHost=null,
  moonrakerPort=7125,
  config={},
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  local configJson = {
    instancesDB: 'moonraker',
    instances: if moonrakerHost == null then [] else [{ hostname: moonrakerHost, port: moonrakerPort }],
  } + config;
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  // The unprivileged image's nginx listens on 8080 as uid 101.
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // A single file mounted into the web root beside the app's assets, not over them.
  + (
    if moonrakerHost == null && config == {} then {} else
      kurly.config({ 'config.json': std.manifestJsonEx(configJson, '  ') }, mountPath='/usr/share/nginx/html', subPath=true)
  )
  + kurly.env(env)
  // The image's own nginx user; every path it writes is a scratch below.
  + kurly.runAs(101, gid=101, fsGroup=101)
  // nginx keeps its pid and every temp path under /tmp in this image; a scratch
  // there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/tmp', '32Mi')
  // Writes under /var/cache/nginx; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/cache/nginx', '32Mi')
  // The entrypoint substitutes environment into its nginx configuration, which the
  // Service-link environment would fill with tcp:// URLs nginx rejects.
  + kurly.disableServiceLinks()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
