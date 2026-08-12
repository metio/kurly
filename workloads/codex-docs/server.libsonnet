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
// THE CONFIGURATION FILE IS MANDATORY AND THE IMAGE DOES NOT SHIP ONE. codex.docs
// merges its built-in defaults over one docs-config.yaml, but the loader OPENS
// that file before merging anything: without it the process throws ENOENT and
// exits, so a workload that mounts nothing crash-loops rather than running on
// defaults. kurly therefore always renders one, carrying the site settings.
//
// AUTHENTICATION IS NOT IN IT, AND UNTIL YOU SUPPLY IT THE EDITOR IS OPEN ON THE
// IMAGE'S OWN PUBLISHED PASSWORD. The same file holds `auth.password` (the single
// password gating every edit) and `auth.secret` (the session key), and both fall
// back to the values printed in the upstream source when the file omits them.
// kurly will not write a credential, so `secretName` names a Secret with a
// docs-config.yaml key holding the WHOLE file, which is mounted instead of the
// rendered one — the settings and the credentials travel together because
// splitting them would mean parsing and reassembling somebody's configuration.
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
  // A Secret with a docs-config.yaml key — the whole configuration file,
  // credentials included. Given, it replaces the rendered one entirely.
  secretName=null,
  title='CodeX Docs',
  description='Documentation powered by Editor.js',
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
  // Mounted as a single FILE, never as a directory: the path sits inside the
  // application's own install tree, and shadowing that directory would hide the
  // code beside it.
  + (
    if secretName != null
    then kurly.secretMount(secretName, '/usr/src/app/docs-config.yaml', subPath='docs-config.yaml')
    else kurly.config({
      'docs-config.yaml': std.manifestYamlDoc({
        port: 3000,
        uploads: { driver: 'local', 'local': { path: './uploads' } },
        database: { driver: 'local', 'local': { path: './db' } },
        frontend: { title: title, description: description },
      }, quote_keys=false),
      // subPath names the DIRECTORY and mounts each file into it individually —
      // the install tree stays visible, which mounting a volume over
      // /usr/src/app would not.
    }, mountPath='/usr/src/app', subPath=true)
  )
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
