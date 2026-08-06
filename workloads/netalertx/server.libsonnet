// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// netalertx — a NetAlertX server (scans a network, keeps an inventory of the
// devices it finds, and notifies when one appears, disappears or changes). A
// plain composable kurly.http workload keeping its configuration and SQLite
// database on a PersistentVolume. Import it and render with kurly.list:
//
//   local netalertx = import 'github.com/metio/kurly/workloads/netalertx/server.libsonnet';
//   kurly.list(netalertx())
//
// Serves the web UI and API on :20211 — compose an exposure onto it.
//
// WHAT IT CAN SEE IS THE POD'S NETWORK, not the network the operator has in
// mind. A pod on a CNI overlay scans the overlay: arp-scan reaches the pod
// subnet and nothing behind it, so a default deployment inventories other pods
// rather than the LAN. Reaching real devices means putting the pod on the host's
// network (host networking plus NET_RAW/NET_ADMIN, which leaves the restricted
// posture behind) or pointing the scan at a routable range the cluster can
// reach. Deployed as it stands, it runs and finds very little — which reads like
// a broken install and is not one.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='netalertx',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(20211)
  + kurly.servicePort(20211)
  + (if env == {} then {} else kurly.env(env))
  // The image's own environment is entirely NETALERTX_*-prefixed, and a Service
  // called netalertx makes Kubernetes inject NETALERTX_PORT as a tcp:// URL into
  // the same namespace of names the application reads its paths from.
  + kurly.disableServiceLinks()
  // The entrypoint runs as root: it prepares /data for the netalertx account and
  // drops to it with su-exec, and the scanning binaries carry file capabilities
  // it must be able to gain on exec. There is no path through that as an
  // unprivileged process.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  // The image AUDITS its own capability set at startup and REFUSES TO BOOT with
  // anything beyond this list — so keeping the default set (the usual shape for
  // an entrypoint that drops privileges) fails immediately, and these six are the
  // set the image itself names: three for the drop, three for the scanners.
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID', 'NET_ADMIN', 'NET_BIND_SERVICE', 'NET_RAW'])
  // Configuration (app.conf) and the SQLite database both live under /data, so a
  // single volume mounted there persists everything.
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // Everything else it writes — the rendered nginx configuration, the php-fpm and
  // supercronic run directories, the logs and the API snapshots — the image
  // already points at /tmp, so the root filesystem stays read-only.
  + kurly.scratch('/tmp', '256Mi')
  // The first boot renders the nginx configuration, creates the database and runs
  // the initial scan before anything answers, so the budget is a startup probe
  // rather than a long liveness delay.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  // By connection: the UI answers a redirect on / and the API wants a token, so
  // any path-based probe judges the wrong thing.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
