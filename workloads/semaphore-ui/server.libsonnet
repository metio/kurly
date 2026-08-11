// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// semaphore-ui — a web interface for running Ansible playbooks, Terraform plans
// and shell scripts, with projects, schedules and an audit trail. A plain
// composable kurly.http workload: the default database is BoltDB in a file on a
// PersistentVolume, so a single instance needs no external database. Import it
// and render with kurly.list:
//
//   local semaphore = import 'github.com/metio/kurly/workloads/semaphore-ui/server.libsonnet';
//   kurly.list(semaphore(secretName='semaphore'))
//
// Serves the web UI and API on :3000 — compose an exposure onto it.
//
// SECRETS: `secretName` is required in any real deployment. It carries
// SEMAPHORE_ACCESS_KEY_ENCRYPTION, the key every SSH key and cloud credential
// Semaphore stores is encrypted with — CHANGING IT MAKES THE STORED KEYS
// UNREADABLE, so it belongs in a Secret from the first boot rather than being
// left to a default — and SEMAPHORE_ADMIN_PASSWORD, the first user's password.
//
// WHAT IT RUNS: playbooks execute as child processes IN THIS CONTAINER, against
// whatever the pod can reach. The image ships Ansible; anything else a playbook
// calls has to be there too.
//
// Single writer: one BoltDB file on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two servers off the file. Point
// dbDialect/dbHost at PostgreSQL or MySQL to run more than one.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='semaphore-ui',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // bolt (the file database on the volume), postgres or mysql.
  dbDialect='bolt',
  dbHost=null,
  dbName='semaphore',
  dbUser='semaphore',
  // A Secret carrying SEMAPHORE_ACCESS_KEY_ENCRYPTION, SEMAPHORE_ADMIN_PASSWORD
  // and, for an external database, SEMAPHORE_DB_PASS.
  secretName=null,
  adminName='admin',
  adminEmail='admin@example.com',
  // The URL a browser reaches this at; Semaphore builds its links from it.
  publicUrl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(
    {
      SEMAPHORE_DB_DIALECT: dbDialect,
      SEMAPHORE_DB_PATH: '/var/lib/semaphore',
      SEMAPHORE_CONFIG_PATH: '/etc/semaphore',
      SEMAPHORE_TMP_PATH: '/tmp/semaphore',
      SEMAPHORE_PORT: '3000',
      SEMAPHORE_ADMIN: adminName,
      SEMAPHORE_ADMIN_NAME: adminName,
      SEMAPHORE_ADMIN_EMAIL: adminEmail,
    }
    + (if dbHost != null then { SEMAPHORE_DB_HOST: dbHost, SEMAPHORE_DB: dbName, SEMAPHORE_DB_USER: dbUser } else {})
    + (if publicUrl != null then { SEMAPHORE_WEB_ROOT: publicUrl } else {})
    + env
  )
  // The uid the image already runs as; fsGroup so the database file and the
  // generated configuration are writable.
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.store('/var/lib/semaphore', storageSize, storageClass=storageClass)
  // The wrapper writes the generated config.json here on every start, and the
  // playbook runner unpacks repositories under the temp path.
  + kurly.scratch('/etc/semaphore', '8Mi')
  + kurly.scratch('/tmp', '1Gi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ httpGet: { path: '/api/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/ping', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
