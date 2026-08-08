// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// routr — a Routr server (a SIP proxy, registrar and location server: it registers
// phones and routes calls between them and the carriers you trunk to). A composable
// kurly.http workload used here for its Deployment and Service plumbing, but Routr
// speaks SIP, not HTTP. Import it and render with kurly.list:
//
//   local routr = import 'github.com/metio/kurly/workloads/routr/server.libsonnet';
//   kurly.list(routr())
//
// Listens on :5060 (TCP and UDP), :5061 (TLS), :5062 (WS), :5063 (WSS) and serves the
// gRPC management API on :51908 — route the SIP ports as TCP/UDP through a LoadBalancer
// or a Gateway TCPRoute/UDPRoute, not an HTTP ingress, and keep :51908 off the public
// internet. SIP is address-sensitive: a proxy behind NAT or a rewriting load balancer
// needs its externally reachable address, which is what EXTERNAL_ADDR is for.
//
// NO VOLUME, DELIBERATELY: the all-in-one image carries an ALREADY INITIALIZED
// PostgreSQL inside its own filesystem and starts it at boot, and the tooling that
// created it (npm, prisma, the migrations) is deleted from the released image — so a
// PersistentVolume mounted over /var/lib/postgresql/data hides the cluster and leaves
// nothing able to recreate it. Agents, domains, trunks and numbers therefore live for
// as long as the pod does, and are configured through the API after each start. Point
// databaseUrl at a PostgreSQL you keep, and the same data survives a restart.
//
// Single instance: registrations are held in an in-memory location service, so a second
// replica would answer for phones it has never seen. One replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

// The signaling transports beyond SIP over TCP on :5060, which kurly.http names 'http'.
local sipPorts = [
  { name: 'sip-udp', port: 5060, protocol: 'UDP' },
  { name: 'sip-tls', port: 5061, protocol: 'TCP' },
  { name: 'sip-ws', port: 5062, protocol: 'TCP' },
  { name: 'sip-wss', port: 5063, protocol: 'TCP' },
  { name: 'api', port: 51908, protocol: 'TCP' },
];

function(
  name='routr',
  image=defaultImage,
  // The PostgreSQL Routr stores its configuration in. The default is the one inside the
  // image, which dies with the pod.
  databaseUrl='postgres://postgres:postgres@localhost:5432/routr',
  // The address other SIP endpoints reach this proxy at. Unset, Routr advertises the pod
  // address, and a phone outside the cluster answers a call by sending media nowhere.
  externalAddr=null,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5060)
  + kurly.servicePort(5060)
  + std.foldl(
    function(ports, p) ports + kurly.extraPort(p.name, p.port, protocol=p.protocol),
    sipPorts,
    {}
  )
  + kurly.env(
    { DATABASE_URL: databaseUrl }
    + (if externalAddr != null then { EXTERNAL_ADDR: externalAddr } else {})
    + env
  )
  // The entrypoint starts the bundled PostgreSQL and then su-execs to the unprivileged
  // service account, which it can only do from root.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // It also rewrites config/edgeport.yaml in place, mints the signaling keystore into
  // /etc/routr/certs, and hands PostgreSQL its data directory and socket — all inside the
  // image's own tree.
  + kurly.writableRootFilesystem()
  // The JVM edgeport is spawned only after the Node services are up, and the first start
  // brings a database up with it, so the port is late rather than broken.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
