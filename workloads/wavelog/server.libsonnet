// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wavelog — a Wavelog server (a web logbook for radio amateurs: contacts, awards,
// statistics and maps). A plain composable kurly.http workload on the official image,
// backed by an external MySQL/MariaDB, with its generated configuration, uploads and
// user data on PersistentVolumes. Import it and render with kurly.list:
//
//   local wavelog = import 'github.com/metio/kurly/workloads/wavelog/server.libsonnet';
//   kurly.list(wavelog())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE: Wavelog needs a MySQL/MariaDB database — the mysql-cluster workload
// provides one. It takes NO database coordinates from the environment: the web
// installer at /install asks for them once and WRITES them into
// application/config/docker, which is why that directory is a volume of its own.
// There is nothing for kurly to mint, so this workload reads no Secret.
//
// The Apache + PHP image's entrypoint runs as root (it renders a php.ini fragment,
// drops the install lock, and chowns the writable directories) and Apache binds :80,
// so this relaxes kurly's non-root and read-only-rootfs defaults; capabilities and
// privilege escalation stay as the entrypoint's chown needs them.
//
// Single writer: the volumes are ReadWriteOnce, so one replica, recreated (never
// rolled) to keep two pods off the same files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='wavelog',
  image=defaultImage,
  // The installer writes database.php and config.php here — lose it and the
  // instance is back at the install wizard.
  configSize='1Gi',
  // QSL card images, eQSL cards and ADIF imports.
  uploadSize='5Gi',
  // Per-user data (LoTW certificates, exports).
  userdataSize='5Gi',
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
  // CI_ENV selects the config directory the installer writes into; the PHP limits
  // are what the project's own image documents for ADIF imports.
  + kurly.env({
    CI_ENV: 'docker',
    PHP_MEMORY_LIMIT: '256M',
    PHP_UPLOAD_MAX_FILESIZE: '64M',
    PHP_POST_MAX_SIZE: '64M',
    PHP_MAX_EXECUTION_TIME: '600',
  } + env)
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // The application caches, logs, writes its .htaccess and the install lock beside
  // its own code, and the entrypoint writes a php.ini fragment.
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/application/config/docker', configSize, storageClass=storageClass)
  + kurly.store('/var/www/html/uploads', uploadSize, storageClass=storageClass)
  + kurly.store('/var/www/html/userdata', userdataSize, storageClass=storageClass)
  // Probe by connection: an unconfigured instance redirects to /install and a
  // configured one to the login page, so no path answers 200 in both states.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
