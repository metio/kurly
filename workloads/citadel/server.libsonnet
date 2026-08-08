// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// citadel — a Citadel server (groupware: mail, calendars, address books, forums
// and instant messaging in one server, reached through its own web interface or
// through the standard mail and chat protocols). A composable kurly.http workload:
// everything Citadel keeps — the database, the message store, the configuration
// and the TLS material — lives in one directory on a PersistentVolume, so it needs
// no external database. Import it and render with kurly.list:
//
//   local citadel = import 'github.com/metio/kurly/workloads/citadel/server.libsonnet';
//   kurly.list(citadel())
//
// Serves the web interface on :80 (and :443) and the mail, news and chat
// protocols beside it — compose an exposure onto the web port, and route the
// protocol ports as TCP through a LoadBalancer or a Gateway TCPRoute. A mail
// server also needs a stable public address and matching DNS; neither is
// something this workload can arrange.
//
// Less hardened, deliberately: ctdlvisor supervises citserver and webcit, binds
// the privileged mail and web ports, and drops to Citadel's own account itself,
// which it can only do starting from root.
//
// Single writer: one Berkeley DB message store on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) — two servers opening the same database is
// how it gets corrupted.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

// The protocol ports Citadel serves beside the primary :80 that kurly.http names
// 'http'. Each name is the shared identity of the container port and its Service
// port, so a route can target it by name.
local protocolPorts = [
  { name: 'https', port: 443 },
  { name: 'smtp', port: 25 },
  { name: 'smtps', port: 465 },
  { name: 'submission', port: 587 },
  { name: 'imap', port: 143 },
  { name: 'imaps', port: 993 },
  { name: 'pop3', port: 110 },
  { name: 'pop3s', port: 995 },
  { name: 'xmpp', port: 5222 },
  { name: 'citadel', port: 504 },
];

function(
  name='citadel',
  image=defaultImage,
  // The database, the message store, the configuration and the TLS material, all
  // under /citadel-data.
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  std.foldl(
    function(app, p) app + kurly.extraPort(p.name, p.port),
    protocolPorts,
    kurly.http(name, image)
    + kurly.version(version)
    + kurly.replicas(1)
    + kurly.recreate()
    + kurly.port(80)
    + kurly.servicePort(80)
    + (if env == {} then {} else kurly.env(env))
    // A Service named after the workload makes Kubernetes inject CITADEL_PORT as
    // a tcp:// URL, and Citadel reads CITADEL_* out of its environment.
    + kurly.disableServiceLinks()
    + kurly.rootUser()
    + kurly.allowPrivilegeEscalation()
    + kurly.keepCapabilities()
    + kurly.store('/citadel-data', storageSize, storageClass=storageClass)
    // First start creates the database and the default rooms before webcit
    // answers, and the web interface redirects anonymous callers into its login
    // flow — so probe by connection rather than by path.
    + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
    + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
    + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
    + kurly.resources(
      requests=std.get(resources, 'requests', {}),
      limits=std.get(resources, 'limits', {}),
    )
    + kurly.labels(labels)
    + kurly.annotations(annotations)
  )
