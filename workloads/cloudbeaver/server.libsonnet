// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cloudbeaver — a CloudBeaver Community server (the browser database console from
// the DBeaver project: connect to PostgreSQL, MySQL, SQLite and the rest, browse
// schemas and run SQL, without installing a desktop client). A plain composable
// kurly.http workload: its whole workspace — configuration, saved connections,
// users and query history — lives on a PersistentVolume, so it needs no external
// database of its own. Import it and render with kurly.list:
//
//   local cloudbeaver = import 'github.com/metio/kurly/workloads/cloudbeaver/server.libsonnet';
//   kurly.list(cloudbeaver())
//
// Serves the web console on :8978 — compose an exposure onto it.
//
// It is a console for databases, not a database: the servers it connects to are
// configured by an administrator at runtime and are not dependencies of this
// workload. Nothing here needs to exist for it to start.
//
// Single writer: one embedded workspace on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='cloudbeaver',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8978)
  + kurly.servicePort(8978)
  + kurly.env(
    {
      // CloudBeaver is an Eclipse application, and Equinox insists on writing its
      // bundle cache and a lock file into the configuration area — which ships
      // inside the image, beside the code, and is read-only here. Left alone it
      // does not start at all: "Unable to create lock manager".
      //
      // So the writable half is moved onto the volume and the shipped one is
      // named as the SHARED, read-only half — Eclipse's own cascaded-configuration
      // arrangement for exactly this, a read-only install with per-instance state
      // elsewhere. The alternative is writableRootFilesystem, which would hand the
      // whole install tree over to get one cache directory.
      JAVA_OPTS: '-Dosgi.configuration.area=/opt/cloudbeaver/workspace/.osgi'
                 + ' -Dosgi.sharedConfiguration.area=/opt/cloudbeaver/server/configuration',
    } + env
  )
  // The image builds a `dbeaver` user at uid/gid 8978 and then never selects it,
  // so it runs as root by default. Naming that identity here is what takes the
  // hardened posture: the account the image already provisioned, rather than an
  // arbitrary uid the application has never seen.
  + kurly.runAs(8978, gid=8978, fsGroup=8978)
  + kurly.store('/opt/cloudbeaver/workspace', storageSize, storageClass=storageClass)
  // A JVM writes its temporary files and its own hsperfdata under /tmp.
  + kurly.scratch('/tmp')
  // The console answers 200 on / without authentication, so the probes ask for
  // the page rather than merely opening a socket — a JVM that has bound the port
  // while Jetty is still assembling its contexts is not yet serving.
  //
  // Starting one is slow (an OSGi framework, then Jetty), and the startup probe is
  // what buys that time: a liveness probe generous enough to cover a cold start
  // would take just as long to notice a hung server later.
  //
  // The timeout is raised off the one-second default on purpose: a JVM answering
  // its first request has classes to load, and a probe that gives up after a
  // second measures the warm-up rather than the health. Three of those in a row is
  // a liveness kill of a server that was only busy starting.
  + kurly.startupProbe({ httpGet: { path: '/', port: 'http' }, failureThreshold: 30, periodSeconds: 10, timeoutSeconds: 5 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' }, timeoutSeconds: 5 })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' }, timeoutSeconds: 5, failureThreshold: 6 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
