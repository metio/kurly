// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// fossbilling — a FOSSBilling server (hosting and billing automation with a client
// area, an admin panel and a full API) on the official Apache/PHP image, backed by
// an external MySQL/MariaDB, with its whole install tree on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local fossbilling = import 'github.com/metio/kurly/workloads/fossbilling/server.libsonnet';
//   kurly.list(fossbilling())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE: FOSSBilling needs a MySQL/MariaDB — the mysql-cluster workload provides
// one. Its credentials are entered in the web installer on first visit, which writes
// them into config.php inside the install tree, so kurly authors no Secret and no
// stage reads one.
//
// Single writer: the install tree lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='fossbilling',
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
  + kurly.env(env)
  // Apache starts as root to bind :80 and drops its workers to www-data, and the
  // bundled cron does the same for the five-minute task run. Everything is dropped
  // and these are granted back by name — enough to change identity and to reach the
  // files www-data owns, and nothing else.
  + kurly.rootUser()
  + kurly.addCapabilities(['CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'SETGID', 'SETUID'])
  // Apache keeps its pid and socket under /var/run, cron its own pid file and log,
  // and PHP its sessions under /tmp — none of it data worth keeping, all of it
  // outside the volume, so the filesystem has to accept a write.
  + kurly.writableRootFilesystem()
  // The application, its configuration and its uploads all live in ONE tree:
  // config.php is written next to the code by the web installer, and data/ holds
  // the cache, the logs and the uploads. Upstream persists exactly this path.
  + kurly.store('/var/www/html', storageSize, storageClass=storageClass)
  // /var/www/html ships the whole application, and a PersistentVolume arrives empty
  // and hides it — Apache would serve a directory with no index.php in it. Upstream
  // does not hit this because a Docker NAMED VOLUME is seeded from the image the
  // first time it is used; Kubernetes does no such thing, which is the whole reason
  // this container exists. It mounts the same volume somewhere ELSE, where the
  // image's own tree is still visible, and copies it in.
  //
  // The marker check makes it a first-boot seed: with index.php present the copy is
  // skipped, so an installed instance's config.php and uploads are never overwritten
  // by the image's originals. tar rather than `cp -R`, so dotfiles and the
  // www-data ownership the image set both come across.
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
  // An unconfigured instance answers / with a redirect to the installer, and a
  // configured one validates the Host header, so both probes ask for a connection
  // rather than a status code.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  // The first start copies the whole install tree onto an empty volume before
  // Apache serves anything.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
