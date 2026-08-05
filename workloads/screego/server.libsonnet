// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// screego — a screego server (share your screen with a few people over WebRTC: no
// account, no plugin, a room link and a browser). A plain composable kurly.http
// workload and a stateless one — rooms live in memory for as long as they are
// used, so it claims no volume. Import it and render with kurly.list:
//
//   local screego = import 'github.com/metio/kurly/workloads/screego/server.libsonnet';
//   kurly.list(screego())
//
// Serves the app on :5050 — compose an exposure onto it. It also carries its own
// TURN server on :3478 (TCP and UDP), which is on the Service and is not HTTP.
//
// TURN IS WHAT MAKES IT WORK ACROSS NETWORKS, and it needs an address it can hand
// out. `externalIp` is that address, and there is no useful default: unset,
// screego advertises something reachable only from inside the cluster, and two
// participants on different networks connect to a room and see nothing — no error,
// just a blank screen where the share should be.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='screego',
  image=defaultImage,
  // The publicly reachable address of the TURN server — an IP, or a hostname
  // screego resolves at startup. REQUIRED: screego refuses to start without it,
  // with `SCREEGO_EXTERNAL_IP or SCREEGO_TURN_EXTERNAL_IP must be set`. It has no
  // default here because every value is wrong somewhere else, and a placeholder
  // would turn a loud startup refusal into a room that silently shows nothing.
  externalIp=null,
  // The Secret holding SCREEGO_SECRET, which signs session cookies. Unset, screego
  // generates one per start and everybody is logged out on every restart.
  secretName='screego',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(5050)
  + kurly.servicePort(5050)
  + kurly.extraPort('turn', 3478)
  + kurly.extraPort('turn-udp', 3478, protocol='UDP')
  + kurly.env(
    {
      // Bind every interface: the default listens somewhere the pod alone can
      // reach.
      SCREEGO_SERVER_ADDRESS: '0.0.0.0:5050',
      SCREEGO_TURN_ADDRESS: '0.0.0.0:3478',
    }
    + (if externalIp == null then {} else { SCREEGO_EXTERNAL_IP: externalIp })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image already selects an unprivileged uid and writes nothing, so the
  // hardened posture holds untouched — no volume, no scratch, nothing relaxed.
  + kurly.runAs(1001, gid=1001)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
