// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ejabberd — an ejabberd server (a robust, scalable XMPP/messaging server). A
// plain composable kurly.http workload on the official community image: it keeps
// its Mnesia database and uploads on a PersistentVolume, so it needs no external
// database by default. Import it and render with kurly.list:
//
//   local ejabberd = import 'github.com/metio/kurly/workloads/ejabberd/server.libsonnet';
//   kurly.list(ejabberd())
//
// Serves XMPP client (:5222), server-to-server (:5269), and the admin/HTTP API
// (:5280) — route the XMPP ports as TCP through a LoadBalancer or Gateway
// TCPRoute, and expose :5280 for the admin UI.
//
// CONFIGURATION: ejabberd reads ejabberd.yml from /home/ejabberd/conf. Mount it
// with kurly.config (host, admin, listeners); credentials it references belong in
// a Secret (kurly mints none).
//
// Single writer: the Mnesia database lives on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files. Clustering
// ejabberd across pods needs shared Mnesia/an external database — beyond this
// recipe's default.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

// The XMPP and admin ports beyond the primary client port :5222 that kurly.http
// names 'http'.
local xmppPorts = [
  { name: 's2s', port: 5269 },
  { name: 'admin', port: 5280 },
];

function(
  name='ejabberd',
  image='docker.io/ejabberd/ecs:26.04',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local extraPorts = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { ports+: [{ containerPort: p.port, name: p.name, protocol: 'TCP' } for p in xmppPorts] }
        for container in super.containers
      ],
    } } } },
    service+: { spec+: { ports+: [{ name: p.name, port: p.port, targetPort: p.name, protocol: 'TCP' } for p in xmppPorts] } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5222)
  + kurly.servicePort(5222)
  + (if env == {} then {} else kurly.env(env))
  // The community image runs as uid 9000; pin it and its fsGroup so the database
  // volume is writable and the restricted posture admits the pod.
  + kurly.runAs(9000, gid=9000, fsGroup=9000)
  + kurly.store('/home/ejabberd/database', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + extraPorts
