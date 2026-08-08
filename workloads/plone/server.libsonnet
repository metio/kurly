// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// plone — a Plone backend (a content management system with workflow, versioning
// and per-object permissions, serving its content and the REST API the Volto
// frontend talks to). A plain composable kurly.http workload: the object database
// — Data.fs, its blobs and the template cache — lives on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local plone = import 'github.com/metio/kurly/workloads/plone/server.libsonnet';
//   kurly.list(plone())
//
// Serves Zope on :8080 — compose an exposure onto it.
//
// THE IMAGE SHIPS admin/admin. Zope creates its first Manager account from
// /app/inituser, and the published image carries one naming `admin` with the
// password `admin`; it is created the first time the empty database starts and the
// account then lives in the database, where changing the file no longer reaches
// it. adminSecretName mounts a Secret over that file BEFORE the first start, which
// is the only moment the credential can still be chosen: a key named `inituser`
// holding `<user>:<password>`. Left unset, the instance comes up with the
// published credential and it is on you to change it at once.
//
// site creates a Plone site inside the empty Zope root on start-up and is what
// makes an instance usable at all — without it Zope answers, and there is no CMS
// in it. Creation is skipped when a site of that id already exists, so it is safe
// on every restart; upstream's own banner calls the mechanism unfit for
// production, which is a statement about creating a site while the server boots
// rather than about the site it creates. Leaving it null and running the image's
// `create-site` command once is the deliberate alternative.
//
// The root filesystem is writable because the entrypoint rewrites the instance's
// own configuration at every start — it appends etc/zope.conf.d snippets to
// etc/zope.conf, seds the listen port into etc/zope.ini and regenerates the CORS
// settings — all beside the code in /app.
//
// Single writer: a FileStorage Data.fs on a ReadWriteOnce volume, so one replica,
// recreated (never rolled). Two Zope processes writing one Data.fs corrupt it;
// scaling out is what ZEO or RelStorage are for, and neither is this workload.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='plone',
  image=defaultImage,
  // Data.fs, the blob storage, the template cache and the per-client home.
  storageSize='10Gi',
  storageClass=null,
  // The id of the Plone site created inside the Zope root on start-up, and the
  // path it is then served under. null creates none.
  site='Plone',
  // The distribution the site is created from: `volto` (headless, for the Volto
  // frontend) or `classic` (server-rendered pages).
  distribution='volto',
  // A Secret with an `inituser` key holding `<user>:<password>`, mounted over the
  // image's own /app/inituser. Only the FIRST start of an empty database reads it.
  // kurly mints none.
  adminSecretName=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    (if site == null then {} else { SITE: site, TYPE: distribution })
    + env
  )
  + (
    if adminSecretName == null then {}
    else kurly.secretMount(adminSecretName, '/app/inituser', subPath='inituser')
  )
  // The image's own `plone` account (uid/gid 500) owns /app; the fsGroup is what
  // lets it write the volume it is given, so the entrypoint never needs the root
  // branch that chowns /data and drops back with gosu.
  + kurly.runAs(500, 500, fsGroup=500)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // The entrypoint rewrites etc/zope.conf, etc/zope.ini and the CORS settings in
  // the instance tree at every start.
  + kurly.writableRootFilesystem()
  // A first start compiles the translation catalogs, creates the site and its
  // default content, and only then binds: minutes on an empty database.
  + kurly.startupProbe({ httpGet: { path: '/ok', port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/ok', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/ok', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
