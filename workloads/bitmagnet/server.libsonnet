// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// bitmagnet — a bitmagnet server (a BitTorrent indexer that crawls the DHT,
// classifies what it finds and serves it as a searchable catalogue with a web UI,
// a GraphQL API and Torznab endpoints for the Servarr stack). A composable
// kurly.http workload backed by an EXTERNAL PostgreSQL — the cnpg-cluster workload
// provides one — and holding no state of its own. Import it and render with
// kurly.list:
//
//   local bitmagnet = import 'github.com/metio/kurly/workloads/bitmagnet/server.libsonnet';
//   kurly.list(bitmagnet())
//
// Serves the web app on :3333 — compose an exposure onto it.
//
// PORTS: the DHT crawler speaks to the swarm on :3334, TCP and UDP both, and rides
// onto the Service beside the web port. Crawling needs UNRESTRICTED EGRESS to
// arbitrary internet hosts on arbitrary UDP ports — a NetworkPolicy that allows only
// PostgreSQL leaves the index permanently empty, and the pod looks perfectly healthy
// while it happens.
//
// The single process runs the three services the compose file runs: the HTTP server,
// the queue server and the DHT crawler. Everything it collects is in PostgreSQL, so
// this claims no volume: point database at one that is backed up, and expect it to
// GROW — a crawler indexes for as long as it runs.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='bitmagnet',
  image=defaultImage,
  // The services the worker runs. The default is the set the project's own compose
  // file runs; drop dht_crawler to serve an index without adding to it.
  keys=['http_server', 'queue_server', 'dht_crawler'],
  // The PostgreSQL it connects to. The non-secret coordinates are env; the password
  // lives in the Secret.
  dbHost='bitmagnet-db-rw',
  dbPort=5432,
  database='bitmagnet',
  dbUser='bitmagnet',
  // The Secret holding POSTGRES_PASSWORD. Upstream's compose file publishes the
  // password `postgres`, so supplying this is the difference between a database only
  // this workload can reach and one anybody who has read the repository can.
  secretName='bitmagnet',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(3333)
  + kurly.servicePort(3333)
  + kurly.extraPort('dht-tcp', 3334, protocol='TCP')
  + kurly.extraPort('dht-udp', 3334, protocol='UDP')
  + kurly.args(['worker', 'run'] + ['--keys=%s' % key for key in keys])
  + kurly.env(
    {
      POSTGRES_HOST: dbHost,
      POSTGRES_PORT: std.toString(dbPort),
      POSTGRES_NAME: database,
      POSTGRES_USER: dbUser,
      // The image sets no HOME and runs from /, so the configuration directory the
      // binary resolves would land under the read-only root. Both variables are set
      // because the resolution falls back from one to the other.
      HOME: '/config',
      XDG_CONFIG_HOME: '/config',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The image declares no user, so the hardened default would refuse it outright.
  // Nothing in it needs root: it is one static binary on alpine.
  + kurly.runAs(1000)
  // Where the resolved configuration directory lands, and where the classifier
  // unpacks its work — both beside the code, so the root filesystem stays read-only.
  + kurly.scratch('/config')
  + kurly.scratch('/tmp')
  // A Service named after the workload makes Kubernetes inject BITMAGNET_PORT as a
  // tcp:// URL into the container that reads BITMAGNET_-prefixed settings.
  + kurly.disableServiceLinks()
  // The web UI answers on / but the crawler and the migrations come up first, so the
  // start budget is generous and the running checks are by connection.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
