// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// meshmonitor — a web front end for a Meshtastic mesh: it connects to a node over
// TCP, records the messages, telemetry and node list it sees, and draws them on a
// map and a timeline. A plain composable kurly.http workload: everything it knows
// goes into a SQLite database on a PersistentVolume, so it needs no external
// database. Import it and render with kurly.list:
//
//   local meshmonitor = import 'github.com/metio/kurly/workloads/meshmonitor/server.libsonnet';
//   kurly.list(meshmonitor(nodeIp='10.0.0.42'))
//
// Serves the web UI and API on :3001 — compose an exposure onto it.
//
// IT NEEDS A NODE IT CAN REACH OVER IP. Meshtastic radios are usually attached to
// a device by USB or Bluetooth, neither of which a pod can be given; `nodeIp` is
// the address of a node with the TCP API enabled (an ESP32 node on WiFi, or a
// host running a Meshtastic daemon). Egress from the cluster to that address is a
// prerequisite, and it is the first thing to check when the UI comes up empty.
//
// RUNNING IT UNPRIVILEGED. The image's supervisord declares `user=root` and drops
// to the node user with su-exec, which normally means a root container. It does
// not here: the runtime uid is set to the node user's own 1000, so the su-exec
// call is a change to the uid the process already has, and the entrypoint
// explicitly skips its chown when it is not root because fsGroup has already done
// that job. supervisord's pidfile lives in /var/run, which is a scratch volume, so
// the root filesystem stays read-only.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='meshmonitor',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // The Meshtastic node to connect to, and its TCP API port.
  nodeIp=null,
  nodePort=4403,
  // Set when something terminates TLS in front of this, so the session cookies
  // are marked secure and the client addresses in the log are the real ones.
  behindProxy=true,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '768Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3001)
  + kurly.servicePort(3001)
  + kurly.env(
    { PORT: '3001', DATABASE_PATH: '/data/meshmonitor.db', MESHTASTIC_TCP_PORT: std.toString(nodePort) }
    + (if nodeIp != null then { MESHTASTIC_NODE_IP: nodeIp } else {})
    + (if behindProxy then { TRUST_PROXY: '1', COOKIE_SECURE: 'true' } else {})
    + env
  )
  // The uid the image's own node user carries — see the header for why that is
  // what makes the su-exec in supervisord work without a root container.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The database, the backups and the apprise notification configuration.
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/var/run', '8Mi')
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
