// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// sablier — scales workloads to zero and starts them again on the first request,
// with a waiting page while they come up. A plain composable kurly.http workload:
// it watches and scales other workloads through the Kubernetes API and keeps
// nothing of its own. Import it and render with kurly.list:
//
//   local sablier = import 'github.com/metio/kurly/workloads/sablier/server.libsonnet';
//   kurly.list(sablier())
//
// Serves its API on :10000 — the reverse proxy in front of the scaled workloads
// calls it. Sablier does not proxy traffic itself: a middleware in Traefik,
// Caddy, Nginx, Envoy, Istio or APISIX asks it whether the workload is up, holds
// the request while it starts, and only then forwards.
//
// IT SCALES THINGS, SO THE GRANT IS THE INTERESTING PART. Sablier needs to read
// and change the replica count of the workloads it manages, which is a
// namespace-wide grant on deployments and statefulsets — it cannot be narrowed to
// the ones it manages, because RBAC `resourceNames` cannot express "whichever
// carry the sablier label". apiServerClient declares that grant AND the egress to
// the apiserver together, so a consumer's own rbac() or networkPolicy() composes
// with it rather than firewalling the scaler off from what it scales.
//
// SESSIONS ARE IN MEMORY. Which workloads are currently awake, and for how much
// longer, is process state: a restart forgets it and the next request starts the
// workload again. That is a slow first request rather than an error, so no volume
// — but it is why one replica is the arrangement that behaves predictably, since
// two pods would each hold their own idea of what is running.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='sablier',
  image=defaultImage,
  // How long a workload stays awake after the last request reaches it.
  sessionDuration='5m',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(10000)
  + kurly.servicePort(10000)
  + kurly.args([
    'start',
    '--provider.name=kubernetes',
    '--server.port=10000',
    '--sessions.default-duration=' + sessionDuration,
  ])
  + kurly.env(env)
  // Reading and changing the replica count of the workloads it manages, plus the
  // pods and events it reads to decide whether one is ready. Namespace-wide on
  // those kinds for the reason in the header.
  + kurly.apiServerClient([
    { apiGroups: ['apps'], resources: ['deployments', 'statefulsets'], verbs: ['get', 'list', 'watch', 'update', 'patch'] },
    { apiGroups: ['apps'], resources: ['deployments/scale', 'statefulsets/scale'], verbs: ['get', 'update', 'patch'] },
    { apiGroups: [''], resources: ['pods', 'events'], verbs: ['get', 'list', 'watch'] },
  ])
  // The image ships a single static binary and no user of its own, so any
  // unprivileged uid serves.
  + kurly.runAs(65534, gid=65534)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
