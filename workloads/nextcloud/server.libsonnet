// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// nextcloud — a Nextcloud server (a self-hosted content-collaboration platform: file sync
// and share, calendars, contacts, office documents and a large app ecosystem — your own
// private cloud). A plain composable kurly.http workload on the official Apache image; with
// the default SQLite backend its whole installation (app, config and data) lives on a
// PersistentVolume. Import it, adapt with the parameters below, and render with kurly.list:
//
//   local nextcloud = import 'github.com/metio/kurly/workloads/nextcloud/server.libsonnet';
//   kurly.list(nextcloud())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: SQLite suits a small, single-user instance; a real deployment points
// Nextcloud at an external PostgreSQL/MySQL (the image's POSTGRES_*/MYSQL_* env) and provides
// NEXTCLOUD_ADMIN_USER/NEXTCLOUD_ADMIN_PASSWORD. kurly authors no Secret; provide one holding
// them, pulled in via envFrom. Set NEXTCLOUD_TRUSTED_DOMAINS to your host.
//
// Single writer: the installation lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the files. Use object storage (S3 primary storage) and
// an external database to scale out.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='nextcloud',
  image='docker.io/library/nextcloud:31.0.4',
  storageSize='50Gi',
  storageClass=null,
  trustedDomains=null,
  secretName='nextcloud-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if trustedDomains == null then {} else { NEXTCLOUD_TRUSTED_DOMAINS: trustedDomains };
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
  + kurly.store('/var/www/html', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/status.php', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
