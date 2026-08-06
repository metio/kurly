// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// librephotos-frontend — the built React application of LibrePhotos, served as
// static files by a tiny file server on :3000. It is stateless and holds no
// configuration: the browser reaches the API on the same origin, through the
// proxy stage. One of the three LibrePhotos stages — see the backend stage's
// header and the workload README for the whole picture.
//
//   local frontend = import 'github.com/metio/kurly/workloads/librephotos/frontend.libsonnet';
//   kurly.list(frontend())
//
// Do not expose this directly: the assets alone are not a working install, since
// /api and /media have to come from the same origin. Expose the proxy.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './frontend.image', '\n');

function(
  namePrefix='librephotos',
  name=null,
  image=defaultImage,
  replicas=1,
  env={},
  resources={ requests: { cpu: '20m', memory: '32Mi' }, limits: { memory: '64Mi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-frontend';

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(env)
  // The image's USER is the NAME `static`, which the kubelet cannot check against
  // runAsNonRoot; pin its numeric uid (1000) so the restricted posture admits the
  // pod. Nothing is written at runtime, so the root filesystem stays read-only.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The file server reads its listen port from PORT, a name generic enough that
  // an injected Service-link variable is a hazard rather than a help; it needs
  // none of them either way.
  + kurly.disableServiceLinks()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
