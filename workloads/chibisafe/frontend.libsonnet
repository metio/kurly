// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// chibisafe-frontend — the Next.js application of chibisafe, the half a browser
// actually renders. It is stateless and holds no configuration beyond the address
// of the backend it renders pages against. One of the three chibisafe stages —
// see the server stage's header and the workload README for the whole picture.
//
//   local frontend = import 'github.com/metio/kurly/workloads/chibisafe/frontend.libsonnet';
//   kurly.list(frontend())
//
// Serves on :8001.
//
// Do not expose this directly: the application alone is not a working install,
// since /api, /docs and the uploaded files have to come from the same origin.
// Expose the proxy.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './frontend.image', '\n');

function(
  namePrefix='chibisafe',
  name=null,
  image=defaultImage,
  replicas=2,
  // Where the Next.js server fetches from while rendering a page — an in-cluster
  // address, not the public one. Defaults to the sibling server stage.
  apiUrl=null,
  serverPort=8000,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-frontend';
  local api =
    if apiUrl != null then apiUrl
    else 'http://' + namePrefix + '-server:' + serverPort;

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8001)
  + kurly.servicePort(8001)
  // The image bakes BASE_API_URL as the compose file's host name, which no
  // namespace running two copies can satisfy.
  + kurly.env({ BASE_API_URL: api, HOSTNAME: '0.0.0.0', PORT: '8001' } + env)
  // The image's USER is the NAME `nextjs`, which the kubelet cannot check against
  // runAsNonRoot; pin its numeric uid (1001) so the restricted posture admits the
  // pod.
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  // Next.js reads its listen port from PORT, a name generic enough that an
  // injected Service-link variable is a hazard rather than a help; it needs none
  // of them either way.
  + kurly.disableServiceLinks()
  // The standalone server writes its image and fetch caches beside the build
  // output; a scratch there keeps the root filesystem read-only.
  + kurly.scratch('/app/.next/cache', '1Gi')
  + kurly.scratch('/tmp', '256Mi')
  // Every page is rendered against the backend, and an unreachable one answers
  // with an error page rather than a connection refusal — so probe by connection
  // and let the proxy be the thing that reports the application broken.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
