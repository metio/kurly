// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docassemble — a docassemble server (an expert system that runs guided
// interviews and assembles the documents they produce, written in YAML and
// Python). A composable kurly.http workload running the project's ALL-IN-ONE
// container: PostgreSQL, Redis, RabbitMQ, Apache and the background workers all
// live in the one image, so the workload needs nothing outside the cluster.
// Import it and render with kurly.list:
//
//   local docassemble = import 'github.com/metio/kurly/workloads/docassemble/server.libsonnet';
//   kurly.list(docassemble())
//
// Serves the web application on :80 — compose an exposure onto it.
//
// PERSISTENCE IS THE PROJECT'S OWN BACKUP DIRECTORY, NOT THE DATA DIRECTORIES.
// The container writes its database, its Redis snapshot, its configuration and
// its uploaded files into /usr/share/docassemble/backup as it shuts down, and
// restores all of them from there when it starts — that mechanism exists because
// the image is meant to be thrown away and replaced. Mounting the data
// directories instead would shadow the Python virtualenv and the packaged
// configuration that live beside them in the same tree, and the server would not
// start at all. So the PersistentVolume goes on `backup/`, and the shutdown grace
// period must be long enough for the dump to finish: a pod killed before it
// completes comes back at the last dump it managed, which is the one thing this
// design has to get right.
//
// FIRST START IS SLOW — the container initializes PostgreSQL, runs the schema
// migrations, and compiles its assets before Apache serves anything, which takes
// minutes on a cold node. That is a startupProbe budget, not a liveness delay.
//
// Single writer: one embedded database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='docassemble',
  image=defaultImage,
  // The backup/restore directory the container persists itself through.
  storageSize='20Gi',
  storageClass=null,
  // The hostname browsers reach the server by. Absent unless you say so: a
  // default here would be wrong everywhere it is really deployed, and the server
  // builds the links it mails out from it.
  hostname=null,
  // Set when an ingress, gateway or load balancer terminates TLS and forwards
  // plain HTTP — without it the server hands out http:// links behind an https://
  // address.
  behindHttpsLoadBalancer=true,
  timezone='UTC',
  // Seconds the container is given to dump its database, Redis and files into the
  // backup volume before it is killed.
  shutdownGrace=300,
  // Extra environment, merged last so it wins.
  env={},
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '6Gi' } },
  labels={},
  annotations={},
  podLabels={},
  podAnnotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(
    {
      CONTAINERROLE: 'all',
      TIMEZONE: timezone,
      USEHTTPS: 'false',
      BEHINDHTTPSLOADBALANCER: if behindHttpsLoadBalancer then 'true' else 'false',
    }
    + (if hostname == null then {} else { DAHOSTNAME: hostname })
    + env
  )
  // supervisord starts PostgreSQL, Redis, RabbitMQ, cron, syslog-ng and Apache
  // and drops each to its own account, which it can only do from root; Apache
  // also binds :80.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // Every one of those services keeps its state, sockets and logs inside the
  // image's own tree — the database cluster in /var/lib/postgresql, the
  // configuration in /usr/share/docassemble/config, the installed interviews in
  // the virtualenv itself, which the server updates in place.
  + kurly.writableRootFilesystem()
  + kurly.store('/usr/share/docassemble/backup', storageSize, storageClass=storageClass)
  // The backup runs from the container's own signal handler, so the drain is
  // pointless here and the grace period is everything.
  + kurly.shutdown(grace=shutdownGrace)
  // Probe by connection: the root path redirects to the interview list and answers
  // differently depending on whether anyone is logged in.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 120, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, periodSeconds: 30, failureThreshold: 6 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + kurly.podLabels(podLabels)
  + kurly.podAnnotations(podAnnotations)
