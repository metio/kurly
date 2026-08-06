// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// artalk — an Artalk server (a self-hosted comment system: a small script on a
// page posts to this backend, which keeps the threads, moderates them and sends
// the notifications). A plain composable kurly.http workload keeping its SQLite
// database, its generated configuration and its uploaded images on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local artalk = import 'github.com/metio/kurly/workloads/artalk/server.libsonnet';
//   kurly.list(artalk())
//
// Serves the API and the admin dashboard on :23366 — compose an exposure onto it.
//
// THE FIRST ACCOUNT REGISTERED IS NOT CREATED FOR YOU. Artalk mints the
// administrator through its own CLI (`artalk admin`), so plan on one
// `kubectl exec` after the first roll — nothing here can do it, and until it is
// done the dashboard has nobody to log in as.
//
// siteUrl is the address readers' browsers reach, not the in-cluster Service:
// Artalk builds the links in its notification mails from it, so an unset one
// sends mails pointing nowhere.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='artalk',
  image=defaultImage,
  // The SQLite database, the configuration the entrypoint generates on first
  // start, the log and the uploaded images all live here.
  storageSize='5Gi',
  storageClass=null,
  // The public address of the site the comments belong to, and the name Artalk
  // files them under. Both are deployment facts with no sane default: the mails
  // Artalk sends link back to siteUrl.
  siteUrl=null,
  siteDefault='Default Site',
  locale='en',
  timezone='UTC',
  // The Secret holding ATK_APP_KEY, the key that signs the JWTs users and
  // administrators hold. Artalk generates one into its configuration file when
  // unset, so it survives a restart here but not a move to a fresh volume;
  // supplying it makes sessions outlive the volume.
  secretName='artalk',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(23366)
  + kurly.servicePort(23366)
  + kurly.env(
    {
      TZ: timezone,
      ATK_TIMEZONE: timezone,
      ATK_LOCALE: locale,
      ATK_SITE_DEFAULT: siteDefault,
      // The generated configuration points at ./data/… — relative to the working
      // directory, which is / only because the image sets none. Naming the paths
      // absolutely keeps the database and the log on the volume whatever the
      // entrypoint is invoked from.
      ATK_DB_FILE: '/data/artalk.db',
      ATK_LOG_FILENAME: '/data/artalk.log',
    }
    + (if siteUrl == null then {} else { ATK_SITE_URL: siteUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image selects no account and needs nothing root provides — the binary
  // binds an unprivileged port and writes only under /data.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  // Artalk answers / with its own frontend assets, so an HTTP probe is honest
  // here; it does not redirect and it does not require a session.
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
