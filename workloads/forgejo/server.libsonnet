// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// forgejo — a Forgejo Git forge (a maintained Gitea fork): repository hosting,
// issues, pull requests, and a package/container registry. A plain composable
// kurly.http workload on the ROOTLESS image (so the restricted posture fits),
// with its data on a PersistentVolume and its database external. Import it, point
// it at a database, and render with kurly.list:
//
//   local forgejo = import 'github.com/metio/kurly/workloads/forgejo/server.libsonnet';
//   kurly.list(forgejo(rootUrl='https://git.example.com/'))
//
// Serves the web UI and git-over-HTTP on :3000 and git-over-SSH on :2222 — compose
// an exposure onto the HTTP port, and route TCP :2222 for SSH clones.
//
// DATABASE: Forgejo needs PostgreSQL. This pairs with the cnpg-cluster workload —
// the defaults point at a CNPG cluster named `forgejo-db` (its `-rw` Service) and
// read the password from the `-app` Secret CNPG mints. kurly authors no Secret;
// the database Secret is the consumer's (fillable with kurly.externalSecret).
//
// Single writer: one PersistentVolume holds the repositories, so this is one
// replica, recreated (never rolled) to keep two pods off the ReadWriteOnce volume.
// Horizontal scaling needs shared (RWX) storage, Redis-backed sessions, and the
// external DB — beyond this recipe's default.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

// Forgejo serves the UI and git-over-HTTP on :3000; git-over-SSH runs on :2222
// (an unprivileged port the rootless image can bind), published on the Service
// beside the HTTP port via kurly.extraPort.
function(
  name='forgejo',
  image='codeberg.org/forgejo/forgejo:16.0-rootless',
  storageSize='10Gi',
  storageClass=null,
  dbHost='forgejo-db-rw',
  dbName='forgejo',
  dbUser='forgejo',
  dbSecret='forgejo-db-app',
  // The public base URL Forgejo builds links and clone URLs against. Left null,
  // Forgejo infers it from the request — fine for a first bring-up.
  rootUrl=null,
  // Extra FORGEJO__section__KEY (or GITEA__…) settings, merged over the below. For
  // sessions and tokens to survive a restart, provide FORGEJO__security__SECRET_KEY
  // and __oauth2__JWT_SECRET here from a Secret rather than letting Forgejo mint
  // ephemeral ones.
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    // Keep the generated app.ini (with its SECRET_KEY/INTERNAL_TOKEN) on the data
    // volume so it survives restarts, leaving the root filesystem read-only.
    GITEA_WORK_DIR: '/var/lib/gitea',
    GITEA_APP_INI: '/var/lib/gitea/conf/app.ini',
    FORGEJO__database__DB_TYPE: 'postgres',
    FORGEJO__database__HOST: dbHost + ':5432',
    FORGEJO__database__NAME: dbName,
    FORGEJO__database__USER: dbUser,
    // Read the password from the mounted Secret rather than baking it into env.
    FORGEJO__database__PASSWD__FILE: '/etc/forgejo/secrets/password',
    FORGEJO__server__SSH_PORT: '2222',
    FORGEJO__server__SSH_LISTEN_PORT: '2222',
  } + (if rootUrl == null then {} else { FORGEJO__server__ROOT_URL: rootUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.extraPort('ssh', 2222)
  + kurly.env(baseEnv + env)
  // The rootless image runs as uid 1000; pin it and its fsGroup so the data volume
  // is writable and the restricted posture admits the pod.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/lib/gitea', storageSize, storageClass=storageClass)
  // git and Forgejo write temp files; keep the root filesystem read-only with a
  // scratch /tmp.
  + kurly.scratch('/tmp', '256Mi')
  // The DB password Secret the consumer provides, mounted read-only.
  + kurly.secretMount(dbSecret, '/etc/forgejo/secrets')
  + kurly.readinessProbe({ httpGet: { path: '/api/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/healthz', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
