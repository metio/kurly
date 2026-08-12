// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// codex-docs — a documentation site you write in the browser, built on the
// Editor.js block editor. A plain composable kurly.http workload: pages go to a
// local file database and uploads to a directory beside it, both on a
// PersistentVolume, so it needs no external database. Import it and render with
// kurly.list:
//
//   local codexDocs = import 'github.com/metio/kurly/workloads/codex-docs/server.libsonnet';
//   kurly.list(codexDocs(secretName='codex-docs'))
//
// Serves the site and the editor on :3000 — compose an exposure onto it.
//
// THE CONFIGURATION FILE CARRIES THE ADMIN PASSWORD, SO IT COMES FROM A SECRET,
// NOT A CONFIGMAP. codex.docs takes one docs-config.yaml holding the site
// settings AND the `auth.password` that gates editing along with the session
// secret. kurly renders no ConfigMap for it: `secretName` names a Secret with a
// docs-config.yaml key, which is mounted over the image's own copy. Splitting the
// file so the harmless half could be a ConfigMap would mean parsing and
// reassembling somebody's configuration, and the whole file in a Secret is
// simpler and leaks nothing.
//
// ANYBODY WHO KNOWS THE PASSWORD CAN EDIT EVERY PAGE. There are no user accounts
// — one password, no roles, no audit. That suits a small team's handbook and does
// not suit a public wiki.
//
// Single writer: one file database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='codex-docs',
  image=defaultImage,
  storageSize='2Gi',
  uploadsSize='10Gi',
  storageClass=null,
  // A Secret with a docs-config.yaml key — the whole configuration file.
  secretName=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(env)
  // The image runs node as root by default; nothing in it is owned by a runtime
  // user, so an unprivileged uid with fsGroup over the data volume serves.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Two claims, because the pages and the images that go in them are siblings of
  // the application tree rather than one directory: the file database at db/ and
  // the uploads at uploads/, both relative paths inside the read-only image.
  + kurly.store('/usr/src/app/db', storageSize, storageClass=storageClass)
  + kurly.store('/usr/src/app/uploads', uploadsSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '128Mi')
  + (if secretName != null then kurly.secretMount(secretName, '/usr/src/app/docs-config.yaml', subPath='docs-config.yaml') else {})
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
