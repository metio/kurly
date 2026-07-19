// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mautic — a Mautic server (open-source marketing automation). A plain composable
// kurly.http workload on the official Apache image, backed by an external
// MySQL/MariaDB, with its configuration and uploaded media on a PersistentVolume.
// Import it, point it at a database, and render with kurly.list:
//
//   local mautic = import 'github.com/metio/kurly/workloads/mautic/server.libsonnet';
//   kurly.list(mautic(siteUrl='https://mautic.example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: Mautic needs a MySQL/MariaDB database (kurly ships no MySQL
// recipe — bring your own). It reads MAUTIC_DB_HOST, MAUTIC_DB_NAME, MAUTIC_DB_USER
// from env and MAUTIC_DB_PASSWORD from a provided Secret via envFrom. kurly authors
// no Secret.
//
// The Apache + PHP image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: configuration and media live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='mautic',
  image='docker.io/mautic/mautic:5.2.11-apache',
  storageSize='5Gi',
  storageClass=null,
  dbHost='mautic-db',
  dbName='mautic',
  dbUser='mautic',
  // The public URL Mautic builds links against.
  siteUrl=null,
  // The Secret holding MAUTIC_DB_PASSWORD (kurly mints none), via envFrom.
  secretName='mautic-secrets',
  // Run Mautic's background cron jobs (segments, campaigns, emails) in-container.
  runCronJobs=true,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    MAUTIC_DB_HOST: dbHost,
    MAUTIC_DB_PORT: '3306',
    MAUTIC_DB_NAME: dbName,
    MAUTIC_DB_USER: dbUser,
    MAUTIC_RUN_CRON_JOBS: (if runCronJobs then 'true' else 'false'),
  } + (if siteUrl == null then {} else { MAUTIC_URL: siteUrl });

  // Mautic keeps its generated config and its uploaded media in two trees;
  // surface the media tree as a subpath of the same volume as the config.
  local mediaMount = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [{ name: 'store', mountPath: '/var/www/html/docroot/media', subPath: 'media' }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + mediaMount
