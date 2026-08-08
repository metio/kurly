// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// sosse — a Sosse server (Selenium Open Source Search Engine: it crawls sites
// with a headless browser, keeps its own copies of the pages, and searches that
// archive offline). A composable kurly.http workload backed by an EXTERNAL
// PostgreSQL — the cnpg-cluster workload provides one — with the archive
// (screenshots, HTML snapshots, static files) on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local sosse = import 'github.com/metio/kurly/workloads/sosse/server.libsonnet';
//   kurly.list(sosse())
//
// Serves the web UI and the search API on :80 — compose an exposure onto it.
//
// THE IMAGE SHIPS ITS OWN POSTGRESQL and its default command starts it. That
// bundled server is deliberately NOT used: its data would live in the image's
// /var/lib/postgresql, upgrades between major versions happen inside the
// container, and nothing in a cluster can back it up. The command is therefore
// overridden to /run.sh — the entrypoint one layer down, which waits for
// SOSSE_DB_HOST to answer, migrates, and starts uwsgi, nginx and the crawler.
//
// CONFIGURATION: every option of sosse.conf can be set as SOSSE_<option> in the
// environment, and the environment wins over the file. That matters here because
// the entrypoint writes a default sosse.conf carrying a published db_pass on first
// start; the env var supplied from the Secret overrides it.
//
// Single writer: the archive lives on a ReadWriteOnce volume and one crawler runs
// beside the web server in the same container, so one replica, recreated (never
// rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='sosse',
  image=defaultImage,
  // Screenshots, HTML snapshots, collected static files and crawler scripts.
  storageSize='20Gi',
  storageClass=null,
  // The PostgreSQL it connects to. The coordinates are env; the password lives in
  // the Secret.
  dbHost='sosse-db-rw',
  dbPort=5432,
  database='sosse',
  dbUser='sosse',
  // The Secret holding SOSSE_DB_PASS. Sosse's own default is the published literal
  // `sosse`, so supplying this is the difference between a database anybody on the
  // network can open and one they cannot.
  secretName='sosse',
  // Merged over the defaults below, so a key set here wins. Any sosse.conf option
  // works as SOSSE_<option> (SOSSE_PROXY, SOSSE_CHROMIUM_OPTIONS, …).
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '3Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  // Skip the image's default command, which starts the bundled PostgreSQL before
  // handing over to /run.sh, the entrypoint that actually brings Sosse up.
  //
  // The sudoers drop-in is what makes the external database reach every part of
  // the start-up. /run.sh runs one of its steps as `sudo -u www-data`, and sudo
  // resets the environment, so that step alone loses SOSSE_DB_* and falls back to
  // the configuration file's 127.0.0.1 — where nothing listens once the bundled
  // server is skipped. It fails with a Django traceback while every other step
  // succeeds and the pod still goes Ready, so the loss is invisible unless the
  // logs are read: the MIME handlers the crawler dispatches on are simply never
  // loaded.
  + kurly.command([
    '/usr/bin/bash',
    '-c',
    |||
      printf 'Defaults env_keep += "SOSSE_DB_HOST SOSSE_DB_PORT SOSSE_DB_NAME SOSSE_DB_USER SOSSE_DB_PASS"\n' >/etc/sudoers.d/sosse-db
      chmod 0440 /etc/sudoers.d/sosse-db
      exec /usr/bin/bash /run.sh
    |||,
  ])
  + kurly.env(
    {
      SOSSE_DB_HOST: dbHost,
      SOSSE_DB_PORT: std.toString(dbPort),
      SOSSE_DB_NAME: database,
      SOSSE_DB_USER: dbUser,
    } + env
  )
  + kurly.envFromSecret(secretName)
  // A Service named after the workload makes Kubernetes inject SOSSE_PORT and
  // friends, and Sosse reads every SOSSE_-prefixed variable as a configuration
  // option — the link variables would land in its configuration as nonsense.
  + kurly.disableServiceLinks()
  // The entrypoint runs as root: it writes /etc/sosse/sosse.conf, creates and
  // chowns /run/sosse, /var/log/sosse and the data directory, then drops to
  // www-data with sudo for the crawler and to uwsgi's --uid for the application.
  // nginx also binds :80 from its root master process.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // Configuration, logs, the uwsgi socket and nginx's temporary bodies are all
  // written inside the image's own tree, none of it worth a volume.
  + kurly.writableRootFilesystem()
  // Screenshots, HTML snapshots, collected static files and crawler scripts.
  + kurly.store('/var/lib/sosse', storageSize, storageClass=storageClass)
  // The crawler drives a real headless browser, which will not fit in the 64MiB of
  // shared memory a container gets by default.
  + kurly.scratch('/dev/shm', '256Mi')
  // The first start waits for PostgreSQL, collects static files, applies the whole
  // Django migration set and loads the search-engine and MIME definitions before
  // anything listens. Probe by connection: the UI answers a redirect to the login
  // page on every path an unauthenticated probe could ask for.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 30, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
