// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// omnitools — an OmniTools server (a self-hosted collection of everyday utilities:
// image and video conversion, PDF tools, text and JSON formatting, encoders and
// generators). A plain composable kurly.http workload, and about as small as one
// gets here: nginx serving a static bundle, no database, no volume, no Secret.
// Import it and render with kurly.list:
//
//   local omnitools = import 'github.com/metio/kurly/workloads/omnitools/server.libsonnet';
//   kurly.list(omnitools())
//
// Serves the app on :80 — compose an exposure onto it.
//
// EVERY TOOL RUNS IN THE BROWSER. Files are processed client-side and never
// uploaded, so this workload holds no user data at any point: nothing to back up,
// nothing to leak, and no reason it cannot be scaled out or run as a spot
// workload. That is a property of the software, not a default chosen here.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='omnitools',
  image=defaultImage,
  replicas=1,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  // The image's nginx listens on 80, which an unprivileged process may not bind.
  // Rather than run the whole server as root to obtain one privileged port, this
  // names the account the image already builds and grants back the single
  // capability that binding it needs — everything else stays dropped.
  + kurly.runAs(101, gid=101)
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  // nginx writes its pid, its temporary bodies and its caches; none of it outlives
  // the pod, so all of it is scratch rather than a volume.
  + kurly.scratch('/var/cache/nginx')
  + kurly.scratch('/var/run')
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
