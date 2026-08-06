// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// libretime — the LibreTime API server (radio broadcast automation: a programme
// calendar, a media library and scheduled or live playout). A plain composable
// kurly.http workload on the project's libretime-api image: gunicorn serving the
// REST API on :9001, its media library on a PersistentVolume, and its PostgreSQL
// and RabbitMQ external. Import it, point it at both, and render with kurly.list:
//
//   local libretime = import 'github.com/metio/kurly/workloads/libretime/server.libsonnet';
//   kurly.list(libretime(publicUrl='https://radio.example.com'))
//
// Serves the API on :9001 — compose an exposure onto it.
//
// DATABASE & BROKER: LibreTime needs PostgreSQL and RabbitMQ. The defaults point at
// a CNPG cluster named `libretime-db` (its `-rw` Service) and a RabbitMQ named
// `libretime-broker`.
//
// CONFIG IS ONE DOCUMENT: every LibreTime component reads the same
// /etc/libretime/config.yml — there is no environment-variable form of it — so the
// `config` parameter is LibreTime's own schema, rendered to that file verbatim
// (kurly does not model it; a second-hand copy would drift). The default wires the
// database, the broker and the storage path from the parameters beside it. Because
// the document carries the database and broker passwords, `secretName` mounts a
// consumer-provided Secret holding a complete `config.yml` OVER the ConfigMap
// instead — the way to keep those out of a ConfigMap; kurly mints no Secret.
//
// THE OTHER COMPONENTS: a full station also runs playout, liquidsoap, analyzer, a
// worker and the legacy PHP interface, each its own image sharing this media
// volume. This stage carries the API alone — the piece everything else talks to.
//
// Single writer: the media library lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='libretime',
  image=defaultImage,
  storageSize='20Gi',
  storageClass=null,
  // The URL listeners and the other components reach this station at. LibreTime
  // requires it and derives stream URLs from it.
  publicUrl='https://libretime.example.com',
  // The two shared secrets of a station: the internal API key the components
  // authenticate with, and Django's SECRET_KEY. Replace both — anything reachable
  // that keeps these is unauthenticated.
  apiKey='changeme',
  secretKey='changeme',
  timezone='UTC',
  dbHost='libretime-db-rw',
  dbName='libretime',
  dbUser='libretime',
  dbPassword='libretime',
  brokerHost='libretime-broker',
  brokerVhost='/libretime',
  brokerUser='libretime',
  brokerPassword='libretime',
  // LibreTime's own config.yml schema, rendered verbatim. Defaults to the document
  // built from the parameters above.
  config=null,
  // A Secret holding a complete `config.yml`, mounted over /etc/libretime. Set it to
  // keep the database and broker passwords out of the ConfigMap; kurly mints none.
  secretName=null,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local defaultConfig = {
    general: {
      public_url: publicUrl,
      api_key: apiKey,
      secret_key: secretKey,
      timezone: timezone,
    },
    storage: { path: '/srv/libretime' },
    database: { host: dbHost, port: 5432, name: dbName, user: dbUser, password: dbPassword },
    rabbitmq: { host: brokerHost, port: 5672, vhost: brokerVhost, user: brokerUser, password: brokerPassword },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // gunicorn binds 0.0.0.0:9001 in the image's own command.
  + kurly.port(9001)
  + kurly.servicePort(9001)
  + kurly.env(env)
  // The image creates and runs as uid 1000, which owns /etc/libretime and the
  // storage directory; pin it and its fsGroup so the media volume is writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/srv/libretime', storageSize, storageClass=storageClass)
  // gunicorn writes its worker heartbeat files to a temporary directory.
  + kurly.scratch('/tmp', '128Mi')
  + (
    if secretName != null
    then kurly.secretMount(secretName, '/etc/libretime')
    else kurly.config(
      { 'config.yml': std.manifestYamlDoc(if config != null then config else defaultConfig) },
      mountPath='/etc/libretime',
    )
  )
  // /api/v2/version is the image's own health check and answers unauthenticated.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ httpGet: { path: '/api/v2/version', port: 'http' }, periodSeconds: 15 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 30, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
