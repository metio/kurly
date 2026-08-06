// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// atheos — an Atheos server (a web-based IDE with a small footprint, continued from
// Codiad) on the maintainer's Apache/PHP image, with its whole install tree on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local atheos = import 'github.com/metio/kurly/workloads/atheos/server.libsonnet';
//   kurly.list(atheos())
//
// Serves the IDE on :80 — compose an exposure onto it.
//
// IT IS UNCONFIGURED AND OPEN UNTIL YOU FINISH THE INSTALLER. A fresh instance
// answers with its install page, and whoever reaches it first creates the account
// that owns the editor and everything it can write. Finish the installer yourself
// before anyone else can reach it, or put an authenticating proxy in front.
//
// Atheos keeps NO database: its users, projects and sessions live in data/ and the
// edited files in workspace/, both inside the install tree, and the installer writes
// config.php next to the code — so the tree is the state and all of it persists.
//
// Single writer: the tree lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='atheos',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
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
  // Apache starts as root to bind :80 and drops its workers to www-data. Everything
  // is dropped and these are granted back by name — enough to change identity and to
  // reach the files www-data owns, and nothing else.
  + kurly.rootUser()
  + kurly.addCapabilities(['CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'SETGID', 'SETUID'])
  // Apache keeps its pid, its sockets and its logs under /var/run and /var/log, and
  // PHP its sessions under /var/lib/php — none of it state worth keeping, all of it
  // outside the volume, so the filesystem has to accept a write.
  + kurly.writableRootFilesystem()
  // Code, config.php, data/ and workspace/ are ONE tree, so the volume is the whole
  // document root — the same path the image declares as its volume.
  + kurly.store('/var/www/html', storageSize, storageClass=storageClass)
  // /var/www/html ships the whole application, and a PersistentVolume arrives empty
  // and hides it — Apache would serve a directory with no index.php in it. A Docker
  // named volume is seeded from the image on first use and Kubernetes does no such
  // thing, which is the whole reason this container exists: it mounts the same volume
  // somewhere ELSE, where the image's tree is still visible, and copies it in.
  //
  // The marker check makes it a first-boot seed: with index.php present the copy is
  // skipped, so an installed instance's config.php, users and workspace are never
  // overwritten by the image's originals. tar rather than `cp -R`, so the dotfiles
  // (.htaccess drives the routing) and the www-data ownership both come across.
  + kurly.initContainer({
    name: 'seed-app',
    image: image,
    command: [
      'sh',
      '-c',
      '[ -f /seed/index.php ] || (cd /var/www/html && tar cf - . | tar xf - -C /seed)',
    ],
    volumeMounts: [{ name: 'store', mountPath: '/seed' }],
  })
  // An unconfigured instance answers / with a redirect to the installer, so both
  // probes ask for a connection rather than a status code.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  // The first start copies the whole install tree onto an empty volume before Apache
  // serves anything.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
