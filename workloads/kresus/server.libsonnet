// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kresus — a Kresus server (a personal finance manager: it aggregates bank
// accounts through woob, categorises what arrives and budgets against it). A
// composable kurly.http workload backed by an EXTERNAL PostgreSQL — the
// cnpg-cluster workload provides one — with woob's downloaded bank modules and
// Kresus' own data directory on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local kresus = import 'github.com/metio/kurly/workloads/kresus/server.libsonnet';
//   kurly.list(kresus())
//
// Serves the web app on :9876 — compose an exposure onto it.
//
// PostgreSQL rather than SQLite because upstream discourages SQLite outright: it
// cannot carry Kresus' migrations across an upgrade, so the cheap default is the
// one that strands the data on the next release.
//
// The image's entrypoint reaches the internet at EVERY start: it pip-installs the
// latest woob and, unless IS_NIGHTLY is set, yarn-upgrades Kresus itself. The
// upgrade is switched off here (IS_NIGHTLY=1) so the pinned tag is what runs, but
// the woob install is not optional and the entrypoint exits on failure — a cluster
// with no egress to PyPI cannot start this pod.
//
// Single writer: one data directory on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='kresus',
  image=defaultImage,
  // Kresus' data directory: woob's downloaded bank modules, its sources list and
  // the log file.
  storageSize='2Gi',
  storageClass=null,
  // The PostgreSQL it connects to. The non-secret coordinates are env; the
  // password lives in the Secret.
  dbHost='kresus-db-rw',
  dbPort=5432,
  database='kresus',
  dbUser='kresus',
  // The Secret holding KRESUS_DB_PASSWORD and KRESUS_SALT. The salt encrypts
  // exports, so a value that changes between deployments makes the exports taken
  // before it unreadable.
  secretName='kresus',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9876)
  + kurly.servicePort(9876)
  + kurly.env(
    {
      HOST: '0.0.0.0',
      PORT: '9876',
      KRESUS_DIR: '/home/user/data',
      KRESUS_DB_TYPE: 'postgres',
      KRESUS_DB_HOST: dbHost,
      KRESUS_DB_PORT: std.toString(dbPort),
      KRESUS_DB_NAME: database,
      KRESUS_DB_USERNAME: dbUser,
      // Keep the entrypoint from yarn-upgrading Kresus over the pinned tag.
      IS_NIGHTLY: '1',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // A Service named after the workload makes Kubernetes inject KRESUS_PORT as a
  // tcp:// URL into a process that reads KRESUS_* as its own configuration.
  + kurly.disableServiceLinks()
  // The entrypoint renumbers the `user` account, writes a git identity, installs
  // woob, chowns the home directory and then drops to `user` with su — all of
  // which it can only do starting from root.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // pip installs woob into the system site-packages, git config writes into
  // /root, and the entrypoint rewrites the permissions of /opt/config.ini.
  + kurly.writableRootFilesystem()
  + kurly.store('/home/user/data', storageSize, storageClass=storageClass)
  // Installing woob and migrating the database is minutes, not seconds, on a
  // first start.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
