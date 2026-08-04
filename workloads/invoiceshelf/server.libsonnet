// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// invoiceshelf — an InvoiceShelf server (self-hosted invoicing and estimates for
// freelancers and small businesses; the maintained continuation of Crater). A
// plain composable kurly.http workload: with the default SQLite backend its
// database, uploads and generated PDFs all live on a PersistentVolume, so it needs
// nothing external. Import it and render with kurly.list:
//
//   local invoiceshelf = import 'github.com/metio/kurly/workloads/invoiceshelf/server.libsonnet';
//   kurly.list(invoiceshelf())
//
// Serves the web app on :8080 — compose an exposure onto it. Point the DB_*
// settings at external PostgreSQL or MySQL through env to move off SQLite; the
// uploads stay on the volume either way.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='invoiceshelf',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // The public URL the application builds links and PDF assets against. No
  // default: every value is wrong somewhere else.
  appUrl=null,
  // The Secret holding APP_KEY, which encrypts session and database values.
  // Supplied rather than generated, because the entrypoint writes a fresh one into
  // its own .env when none is set — and that file is not on the volume, so a
  // restart would mint a new key and orphan everything the old one encrypted.
  // kurly authors no Secret.
  secretName='invoiceshelf',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
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
    {
      // Named explicitly because the entrypoint and the framework disagree
      // otherwise. The entrypoint creates the database under storage/app when
      // DB_DATABASE is unset, while Laravel — reading the shipped .env, where the
      // value is blank — looks for it under database/. The application then waits
      // thirty seconds for a database that was created somewhere else and exits.
      DB_CONNECTION: 'sqlite',
      DB_DATABASE: '/var/www/html/storage/app/database.sqlite',
    }
    + (if appUrl == null then {} else { APP_URL: appUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image already selects www-data (uid 82) rather than running as root, so
  // naming it here changes nothing about who runs — it makes the volume writable
  // by that account, which is what the entrypoint checks for and refuses to start
  // without.
  + kurly.runAs(82, gid=82, fsGroup=82)
  // A Laravel application writes inside its own install tree, and not only where a
  // volume can be mounted: bootstrap/cache holds the compiled config, and the
  // entrypoint creates .env beside the code on first boot. Neither is data worth
  // keeping, so neither gets a volume — but both need the filesystem to accept a
  // write, which is the whole of why this relaxes the read-only default.
  //
  // It keeps every other part of the hardened posture, including running as a
  // non-root user — where kurly's other PHP applications (bookstack, snipe-it)
  // have to give up root as well, because their images start as it.
  + kurly.writableRootFilesystem()
  // storage/ holds the SQLite database, uploads and logs. The entrypoint recreates
  // the framework subdirectories on every start precisely so that a mount over
  // this path is supported — Laravel dies at boot if its compiled-view directory
  // is missing, and a fresh volume arrives without one.
  + kurly.store('/var/www/html/storage', storageSize, storageClass=storageClass)
  // storage/ ships CONTENT, not just empty directories — the PDF templates the
  // invoice renderer loads live in storage/app/templates/pdf — and a
  // PersistentVolume arrives empty and hides them. Laravel then fails to boot on
  // "The /var/www/html/storage/app/templates/pdf directory does not exist".
  //
  // Upstream's compose does not hit this because a Docker NAMED VOLUME is seeded
  // from the image the first time it is used. Kubernetes does no such thing, and
  // that difference is the whole reason this container exists: it mounts the same
  // volume somewhere ELSE, where the image's own storage/ is still visible, and
  // copies it in. `cp -n` never clobbers, so this is a first-boot seed on an empty
  // volume and a no-op on every start after it.
  // It copies with tar rather than cp, which is not a style choice. This image's
  // shell is BusyBox, whose `cp -R src/. dst/` copies NOTHING and exits 0 — so the
  // obvious spelling seeds an empty volume, reports success, and the application
  // then fails on a missing directory several minutes later with nothing pointing
  // back here. The tar pipeline copies all of it, dotfiles included.
  //
  // The guard is what makes it a first-boot seed: with the marker present the
  // whole thing is skipped, so a running instance's own files are never
  // overwritten by the image's empty originals.
  + kurly.initContainer({
    name: 'seed-storage',
    image: image,
    command: [
      'sh',
      '-c',
      '[ -d /seed/app/templates ] || (cd /var/www/html/storage && tar cf - . | tar xf - -C /seed)',
    ],
    volumeMounts: [{ name: 'store', mountPath: '/seed' }],
  })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' }, timeoutSeconds: 5 })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' }, timeoutSeconds: 5, failureThreshold: 6 })
  // The first start copies a database stub, runs migrations and builds the
  // configuration cache before it serves anything.
  + kurly.startupProbe({ httpGet: { path: '/', port: 'http' }, failureThreshold: 30, periodSeconds: 10, timeoutSeconds: 5 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
