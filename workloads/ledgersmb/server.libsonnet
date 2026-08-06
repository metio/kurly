// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ledgersmb — a LedgerSMB server (double-entry accounting and ERP: receivables,
// payables, the general ledger, invoicing, inventory and fixed assets, served as
// a Perl/starman web application). A plain composable kurly.http workload backed
// by an EXTERNAL PostgreSQL — the cnpg-cluster workload provides one. Import it,
// point it at that database, and render with kurly.list:
//
//   local ledgersmb = import 'github.com/metio/kurly/workloads/ledgersmb/server.libsonnet';
//   kurly.list(ledgersmb())
//
// Serves the web application on :5762 — compose an exposure onto it.
//
// NO VOLUME: every company's books, documents and attachments live in
// PostgreSQL, so this stage claims no PersistentVolume. Point dbHost at a
// database that is backed up; nothing on the pod survives a restart and nothing
// needs to.
//
// SETUP IS A WEB STEP, NOT AN ENV CONTRACT: LedgerSMB has no application-level
// database credentials. An operator visits /setup.pl and logs in with a
// PostgreSQL superuser to create each company database, and users then log in
// with their own PostgreSQL roles. That is why this workload reads no Secret —
// there is nothing kurly could put in one.
//
// The container writes its generated ledgersmb.conf into /tmp and starman keeps
// its state beside the application in local/, so both get a scratch volume; the
// root filesystem stays read-only. The image already runs as www-data.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='ledgersmb',
  image=defaultImage,
  // The PostgreSQL it connects to. Credentials are supplied by whoever logs in,
  // so only the coordinates are configuration.
  dbHost='ledgersmb-db-rw',
  dbPort=5432,
  // The company database offered on the login screen by default.
  database='lsmb',
  // Which client addresses may set X-Forwarded-For. The image ships a Docker
  // bridge range, which is meaningless in a cluster; this defaults to the
  // private space a pod network is carved out of. Narrow it to the ingress
  // controller's addresses where you can.
  proxyIp='10.0.0.0/8',
  // Number of starman workers, i.e. concurrent requests this pod serves.
  workers=5,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(5762)
  + kurly.servicePort(5762)
  + kurly.env(
    {
      POSTGRES_HOST: dbHost,
      POSTGRES_PORT: std.toString(dbPort),
      DEFAULT_DB: database,
      PROXY_IP: proxyIp,
      LSMB_WORKERS: std.toString(workers),
      // The image ships __CONTAINER_GATEWAY__ here, a placeholder no cluster
      // resolves; empty makes the entrypoint omit the mail section entirely
      // rather than write a host that fails on every send.
      LSMB_MAIL_SMTPHOST: '',
    } + env
  )
  // The image's USER is the NAME www-data, which kubelet cannot check against
  // runAsNonRoot — it refuses to start the container rather than guess. Debian's
  // www-data is uid/gid 33, and the application's own tree is chowned to it.
  + kurly.runAs(33, gid=33, fsGroup=33)
  // A Service named `postgres` in the same namespace would otherwise inject
  // POSTGRES_PORT=tcp://…, which the entrypoint copies straight into the
  // database port of the generated configuration.
  + kurly.disableServiceLinks()
  // The entrypoint generates /tmp/ledgersmb.conf, and starman and the LaTeX
  // rendering path both write temporary files there.
  + kurly.scratch('/tmp', '256Mi')
  // The application's own writable tree: uploaded and generated documents,
  // per-company configuration overrides and the template cache.
  + kurly.scratch('/srv/ledgersmb/local', '256Mi')
  // Perl loads the whole application before starman binds, and an unconfigured
  // instance answers 302/401 on every path, so both probes ask for a connection
  // rather than a status.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 30, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
