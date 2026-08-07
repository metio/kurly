// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wikidocs — a Wiki|Docs server (a flat-file Markdown wiki that keeps no database:
// pages, revisions, attachments and the configuration are all files under
// datasets/). A plain composable kurly.http workload with datasets/ on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local wikidocs = import 'github.com/metio/kurly/workloads/wikidocs/server.libsonnet';
//   kurly.list(wikidocs())
//
// Serves the wiki on :80 — compose an exposure onto it.
//
// IT IS UNCONFIGURED UNTIL SOMEBODY FINISHES setup.php. With no
// datasets/config.inc.php the instance answers with its setup wizard, and whoever
// reaches it first names the wiki and picks the edit code that authorises every
// later edit. Run the wizard yourself before anyone else can reach it, or put an
// authenticating proxy in front.
//
// Single writer: the files are the state, on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) — two pods writing the same page is not
// something a flat-file store resolves afterwards.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='wikidocs',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  // The entrypoint renumbers the apache account to PUID/PGID, chowns the whole
  // document root and then starts httpd, which binds :80 and drops its workers to
  // apache — all of it from root.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // Apache keeps its pid, its locks and its logs under /run and /var/log inside the
  // image's tree, and PHP its sessions under /tmp, so the filesystem has to accept a
  // write.
  + kurly.writableRootFilesystem()
  // datasets/ is the whole state: the documents, their revisions, the trash, the
  // uploaded attachments and config.inc.php. /datasets is a symlink into it, so the
  // volume goes on the real path.
  + kurly.store('/var/www/localhost/htdocs/datasets', storageSize, storageClass=storageClass)
  // The image ships datasets/ with the documents/ and trash/ directories already in
  // it, and a PersistentVolume arrives empty and hides them — the wizard writes its
  // configuration into a tree those directories are expected to exist in. The init
  // container mounts the same volume elsewhere, where the image's copy is still
  // visible, and copies it across; the marker check makes it a first-boot seed, so a
  // configured wiki's pages are never overwritten by the image's originals.
  + kurly.initContainer({
    name: 'seed-datasets',
    image: image,
    command: [
      'sh',
      '-c',
      '[ -d /seed/documents ] || (cd /var/www/localhost/htdocs/datasets && tar cf - . | tar xf - -C /seed)',
    ],
    volumeMounts: [{ name: 'store', mountPath: '/seed' }],
  })
  // An unconfigured instance redirects / to the setup wizard, so both probes ask for
  // a connection rather than a status code.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
