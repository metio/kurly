// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// piler — an email archiving server (every message a mail system handles, kept
// deduplicated and encrypted for as long as a retention policy says, searchable
// full text and exportable for an audit). A composable kurly.http workload backed
// by an EXTERNAL MySQL/MariaDB, an external memcached and an external Manticore
// Search, with the archive itself and the configuration directory each on their
// own PersistentVolume. Import it and render with kurly.list:
//
//   local piler = import 'github.com/metio/kurly/workloads/piler/server.libsonnet';
//   kurly.list(piler())
//
// Serves the web interface on :80 — compose an exposure onto it. Mail arrives on
// :25, which is SMTP and not HTTP, so no Ingress or HTTPRoute can carry it: the
// mail system in front routes to the Service port directly.
//
// The configuration volume is not a convenience. The entrypoint generates
// /etc/piler/piler.key on first start and every archived message is encrypted with
// it, so losing that volume leaves an archive nothing can read — back it up with
// the store, not instead of it.
//
// Single writer: the archive and the configuration on ReadWriteOnce volumes, so
// one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='piler',
  image=defaultImage,
  // The name the archive answers to. It becomes nginx's server_name, the hostid
  // written into piler.conf and the base URL the web interface builds links from,
  // so it is a deployment-specific value with no sane default anywhere.
  hostname='piler.example.com',
  // The archived messages, deduplicated and encrypted.
  storageSize='50Gi',
  // /etc/piler — piler.conf, the nginx site, config-site.php, the TLS material and
  // piler.key, all generated on first start from the templates the image carries.
  configSize='1Gi',
  storageClass=null,
  // The MySQL/MariaDB it connects to. The non-secret coordinates are env; the
  // password lives in the Secret.
  dbHost='piler-db',
  database='piler',
  dbUser='piler',
  // The memcached the web interface and the archiver share. Not optional: the
  // entrypoint writes MEMCACHED_ENABLED=1 into config-site.php unconditionally.
  memcachedHost='memcached',
  // The Manticore Search server holding the full-text index, addressed on :9306
  // and :9307. It must be started against piler's own manticore.conf — the one
  // this workload's configuration volume holds — since the index definitions are
  // piler's, not Manticore's defaults.
  manticoreHost='manticore',
  // Real-time index. 0 keeps the periodic indexer piler's cron drives; 1 has the
  // archiver write into a Manticore RT index as mail arrives.
  realtimeIndex=false,
  // The Secret holding MYSQL_PASSWORD. ADMIN_USER_PASSWORD_HASH may live here too
  // — it resets the built-in admin account's password on every start, and it is a
  // hash of the password rather than the password, so no generator can mint it.
  secretName='piler',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.extraPort('smtp', 25)
  + kurly.env(
    {
      PILER_HOSTNAME: hostname,
      MYSQL_HOSTNAME: dbHost,
      MYSQL_DATABASE: database,
      MYSQL_USER: dbUser,
      MEMCACHED_HOSTNAME: memcachedHost,
      MANTICORE_HOSTNAME: manticoreHost,
      RT: if realtimeIndex then '1' else '0',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The entrypoint starts as root and stays there: it chowns the generated
  // configuration and TLS material to the piler account, starts cron, php-fpm,
  // nginx and rsyslogd through their init scripts, and each of those drops to its
  // own account. nginx also binds :80 and the archiver :25.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // nginx, php-fpm, cron and rsyslogd all keep their sockets, pids and logs inside
  // the image's own tree, and the entrypoint rewrites the web assets when a path
  // prefix is set.
  + kurly.writableRootFilesystem()
  + kurly.store('/var/piler/store', storageSize, storageClass=storageClass)
  + kurly.store('/etc/piler', configSize, storageClass=storageClass)
  // First start creates the schema in an empty database and generates the key and
  // certificate before anything listens, which a liveness delay would not survive.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  // The web interface redirects an unauthenticated request to the login page and
  // nginx serves this site under one server_name, so both probes ask the port
  // rather than a path.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
