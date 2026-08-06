// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// azuracast — an AzuraCast server (runs an internet radio station: a media
// library, playlists and schedules, live DJ sessions, and the Icecast/Liquidsoap
// stack that actually broadcasts them). A composable kurly.http workload on the
// official all-in-one image, backed by an EXTERNAL MariaDB and an EXTERNAL Redis
// — the mysql-cluster and a cache workload provide them — with the station media
// library on a PersistentVolume. Import it and render with kurly.list:
//
//   local azuracast = import 'github.com/metio/kurly/workloads/azuracast/server.libsonnet';
//   kurly.list(azuracast())
//
// Serves the web app and API on :80 — compose an exposure onto it. Each station
// ALSO broadcasts on its own TCP port starting at 8000, which is a plain stream
// and not HTTP: `stationPorts` publishes that range on the Service, and reaching
// it from outside needs a TCP route, not the HTTP exposure the web app takes.
//
// The image runs supervisord as root and drops privileges to the azuracast
// account per service (nginx, php-fpm, Liquidsoap, Icecast), and its entrypoint
// chowns the media tree, so this relaxes the non-root and read-only-rootfs
// defaults.
//
// Single writer: the station media library is a ReadWriteOnce volume, so one
// replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='azuracast',
  image=defaultImage,
  // The station media library, recordings and backups.
  storageSize='50Gi',
  storageClass=null,
  // The MariaDB it connects to. The password lives in the Secret.
  dbHost='azuracast-db',
  dbPort=3306,
  database='azuracast',
  dbUser='azuracast',
  // The Redis it uses for sessions, caching and the message queue.
  redisHost='azuracast-cache',
  redisPort=6379,
  redisDatabase=1,
  // How many station broadcast ports to publish, starting at 8000. AzuraCast
  // hands each station a block from that range; a station whose port is not on
  // the Service is audible inside the pod and nowhere else.
  stationPorts=2,
  // The Secret holding MYSQL_PASSWORD.
  secretName='azuracast',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + std.foldl(
    function(app, i) app + kurly.extraPort('radio-%d' % i, 8000 + i),
    std.range(0, stationPorts - 1),
    {}
  )
  + kurly.env(
    {
      APPLICATION_ENV: 'production',
      MYSQL_HOST: dbHost,
      MYSQL_PORT: std.toString(dbPort),
      MYSQL_DATABASE: database,
      MYSQL_USER: dbUser,
      ENABLE_REDIS: 'true',
      REDIS_HOST: redisHost,
      REDIS_PORT: std.toString(redisPort),
      REDIS_DB: std.toString(redisDatabase),
    } + env
  )
  + kurly.envFromSecret(secretName)
  // supervisord starts nginx, php-fpm, Liquidsoap and Icecast together and drops
  // privileges to their accounts, which it can only do from root; the entrypoint
  // also chowns the media tree on the volume.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // php-fpm, nginx and Liquidsoap keep sockets, caches and logs inside the
  // image's own tree.
  + kurly.writableRootFilesystem()
  // Only the station tree is mounted: /var/azuracast also holds the application
  // itself, and a volume over the whole directory hides it.
  + kurly.store('/var/azuracast/stations', storageSize, storageClass=storageClass)
  // A Service named after the workload would inject AZURACAST_PORT as a tcp://
  // URL into the PHP environment.
  + kurly.disableServiceLinks()
  // First boot migrates the database and builds the Liquidsoap configuration
  // before nginx answers anything, and the web app answers the unauthenticated
  // root with a redirect to the setup wizard — so probe by connection.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
