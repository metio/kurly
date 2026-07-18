// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// status-responder — a tiny HTTP service that answers every request with ONE
// fixed status code and message, as a COMPOSABLE app (not a rendered List).
// Deploy it once, globally, and route protected paths to it from a Gateway API
// HTTPRoute to take them off the public internet:
//
//   local responder = import 'github.com/metio/kurly/workloads/status-responder/responder.libsonnet';
//   kurly.list(responder(name='forbidden', statusCode=403, message='forbidden'))
//
// Gateway API has no portable filter that returns a fixed status code, and the
// empty-backendRefs trick the spec says should return 404 is honoured
// inconsistently (Envoy Gateway returns 500), so a real service that always
// answers the same way is the portable way to sink a route. Pair it with
// kurly.expose.guard on the protected workload (route /admin here) and
// kurly.expose.referenceGrant here (let the workload's namespace reach this
// Service). The workload itself stays reachable in-cluster — only the public
// route sends the guarded path here.
//
// Runs hashicorp/http-echo, whose `-status-code`/`-text` flags are the whole
// recipe. No probe: it answers its fixed status on every path, so an HTTP
// readiness probe would mark it unready — a TCP readiness probe watches the
// listener instead.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version. 'dev' locally; the
// release pipeline rewrites it to the calver before packing the source.
local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='forbidden',
  statusCode=403,
  message='forbidden',
  labels={},
  annotations={},
)
  kurly.http(name, 'docker.io/hashicorp/http-echo:1.0')
  + kurly.version(version)
  // http-echo listens on :5678 by default; match the Service to it so a route's
  // backendRef port is 5678.
  + kurly.port(5678)
  + kurly.servicePort(5678)
  + kurly.args(['-text=' + message, '-status-code=' + std.toString(statusCode)])
  // The image ships no non-root user, and the restricted default demands one.
  + kurly.runAs(12345)
  // TCP, not HTTP: the responder answers its fixed status on every path.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests={ cpu: '10m', memory: '28Mi' },
    limits={ memory: '28Mi' },
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
