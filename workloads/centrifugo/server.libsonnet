// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// centrifugo — a Centrifugo server (a real-time messaging server: browsers and
// apps subscribe over WebSocket, SSE or HTTP-streaming, and a backend publishes to
// them over an HTTP/GRPC API). A plain composable kurly.http workload, and an
// unusual one here: it is STATELESS. Channel history and presence are held in
// memory or in Redis, never on disk, so this workload claims no volume at all.
// Import it and render with kurly.list:
//
//   local centrifugo = import 'github.com/metio/kurly/workloads/centrifugo/server.libsonnet';
//   kurly.list(centrifugo())
//
// Serves clients and the HTTP API on :8000 — compose an exposure onto it, and use
// one that does not break long-lived connections: WebSocket and SSE are the point
// of this workload, so an exposure with a short idle timeout silently turns it
// into a reconnect loop.
//
// ONE REPLICA by default, and that is a correctness bound rather than caution.
// Without a broker each instance knows only its own subscribers, so a message
// published to one pod never reaches clients connected to another — a fleet that
// looks healthy and delivers a fraction of its traffic. Point it at Redis
// (CENTRIFUGO_BROKER_ENABLED plus the Redis address) and it scales horizontally.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='centrifugo',
  image=defaultImage,
  // The Secret holding the token key, the API key and the admin credentials.
  // Every one of them authenticates somebody, so kurly mints none of them.
  secretName='centrifugo',
  // The admin web UI. Off by default: it is a full administrative surface, and it
  // is reached on the same port as the client traffic an exposure publishes.
  admin=false,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(
    {
      // Bind to every interface: the default is loopback, which serves the pod
      // itself and nothing else — a container that starts, passes nothing, and
      // reports no error.
      CENTRIFUGO_HTTP_SERVER_ADDRESS: '0.0.0.0',
      CENTRIFUGO_HTTP_SERVER_PORT: '8000',
      // Health and Prometheus endpoints, which the probes and a ServiceMonitor use.
      // The names follow Centrifugo's own flags (`--health.enabled`), not the
      // http_server section these endpoints are served from: an env var it does
      // not recognise is a WARNING in the log and nothing else, so the probe then
      // fails against an endpoint that was never switched on and the pod restarts
      // with a healthy-looking server inside it.
      CENTRIFUGO_HEALTH_ENABLED: 'true',
      CENTRIFUGO_PROMETHEUS_ENABLED: 'true',
    }
    + (if admin then { CENTRIFUGO_ADMIN_ENABLED: 'true' } else {})
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image already selects its own unprivileged account, so the hardened
  // posture holds with nothing relaxed: no volume to own, nothing to write.
  + kurly.runAs(1000, gid=1000)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
