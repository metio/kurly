// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mongooseim — a MongooseIM server (an XMPP server built for messaging at scale,
// with clustering and a GraphQL management API). A plain composable kurly.http
// workload on the official image: it keeps its Mnesia database on a
// PersistentVolume, so it needs no external database by default. Import it and
// render with kurly.list:
//
//   local mongooseim = import 'github.com/metio/kurly/workloads/mongooseim/server.libsonnet';
//   kurly.list(mongooseim())
//
// Serves XMPP client (:5222), server-to-server (:5269) and the HTTP listener
// carrying BOSH and WebSocket (:5280) — route the XMPP ports as TCP through a
// LoadBalancer or a Gateway TCPRoute, and compose an HTTP exposure onto :5280 for
// BOSH/WebSocket clients.
//
// THE NODE NAME IS PINNED, and that is what makes the volume worth having: the
// entrypoint derives the Erlang node from `hostname -s` and puts the Mnesia
// database in /var/lib/mongooseim/Mnesia.<node>, so with the pod name as the
// hostname every replacement pod picks a NEW directory on the same volume and
// starts empty while the old accounts sit there unread. NODE_HOST is therefore set
// to a fixed value, and a consumer changing it moves the database with it.
//
// A WRITABLE ROOT FILESYSTEM, AND THE ACCOUNT THAT OWNS THE TREE: the entrypoint
// rewrites the release's own etc/ (vm.args for the node name, app.config for the
// Mnesia and log paths) with sed -i, and the release creates var/ and log/ beside
// it — all inside the image, outside any volume. So the image tree is writable, and
// the pod runs as 1001:1002, the account those files belong to. Running as ROOT
// instead does NOT work: with ALL capabilities dropped there is no
// CAP_DAC_OVERRIDE, every write into a directory owned by 1001 fails with EACCES,
// and the VM dies on a logger handler it could not open.
//
// CONFIGURATION: /member is the drop-in directory the entrypoint reads —
// mongooseim.toml, app.config, vm.args and vm.dist.args found there are symlinked
// over the shipped ones. It is a scratch volume by default so the entrypoint finds
// the directory it changes into; pass configMount=true to leave the path free and
// compose your own kurly.config('/member') onto the workload.
//
// Single writer: one Mnesia database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled). MongooseIM clusters across nodes, but that wants a
// StatefulSet with per-pod volumes and the entrypoint's JOIN_CLUSTER handshake —
// beyond this recipe's default.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='mongooseim',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  // The Erlang node's host part. It names the Mnesia directory on the volume, so
  // it must stay the same for the data to be found again.
  nodeHost='localhost',
  // Leave /member unmounted for a consumer's own kurly.config('/member').
  configMount=false,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5222)
  + kurly.servicePort(5222)
  + kurly.extraPort('s2s', 5269)
  + kurly.extraPort('bosh', 5280)
  + kurly.env({
    NODE_TYPE: 'sname',
    NODE_NAME: 'mongooseim',
    NODE_HOST: nodeHost,
  } + env)
  // Nothing in the pod reads the <NAME>_PORT variables Kubernetes injects for a
  // Service named after this workload, and an Erlang release started from a shell
  // script is exactly the shape that trips over one.
  + kurly.disableServiceLinks()
  // The entrypoint rewrites the release's configuration in place and the release
  // creates var/ and log/ beside it, so the image tree must be writable.
  + kurly.writableRootFilesystem()
  // Run as the account that OWNS that tree (1001:1002 in the image), not as root:
  // root would be the obvious answer and is the wrong one, because with ALL
  // capabilities dropped it has no CAP_DAC_OVERRIDE and every write into a
  // directory owned by 1001 fails with EACCES — the VM then dies on a logger
  // handler it could not open, which reads as a configuration error.
  + kurly.runAs(1001, gid=1002, fsGroup=1002)
  + kurly.store('/var/lib/mongooseim', storageSize, storageClass=storageClass)
  // The runtime's logs go to /var/log/mongooseim, which the entrypoint creates.
  + kurly.scratch('/var/log/mongooseim', '256Mi')
  + (if configMount then {} else kurly.scratch('/member', '16Mi'))
  // Probe by connection: the XMPP port answers only once the VM has booted and the
  // listeners are up, and an XMPP stream open is not an HTTP request.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  // Booting the Erlang VM, opening Mnesia and starting every listener takes a while
  // on a cold volume, and a liveness probe must not be the thing that measures it.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
