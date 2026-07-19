// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// peertube — a PeerTube server (a decentralized, federated video platform). A plain
// composable kurly.http workload on the official image, backed by an external
// PostgreSQL and Redis, with its videos, uploads, and config on a PersistentVolume.
// Import it, point it at a database and cache, and render with kurly.list:
//
//   local peertube = import 'github.com/metio/kurly/workloads/peertube/server.libsonnet';
//   kurly.list(peertube(webserverHost='videos.example.com'))
//
// Serves the web app and API on :9000 — compose an exposure onto it.
//
// DATABASE, CACHE & SECRETS: PeerTube reads its database and Redis coordinates and
// its secrets from the environment. The non-secret coordinates default to a
// cnpg-cluster named peertube-db and a valkey named peertube-cache; the sensitive
// values (PEERTUBE_DB_PASSWORD, PEERTUBE_SECRET, and the initial root password)
// come from a provided Secret via envFrom. kurly authors no Secret.
//
// Single writer: videos and uploads live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files. Large instances move
// storage to S3-compatible object storage (the seaweedfs workload) — beyond this
// recipe's default.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='peertube',
  image='docker.io/chocobozzz/peertube:v8.2.2-trixie',
  storageSize='50Gi',
  storageClass=null,
  dbHost='peertube-db-rw',
  dbName='peertube',
  dbUser='peertube',
  redisHost='peertube-cache',
  // The public hostname PeerTube serves at (required — federation and links
  // depend on it).
  webserverHost=null,
  // The Secret holding PEERTUBE_DB_PASSWORD, PEERTUBE_SECRET, and
  // PT_INITIAL_ROOT_PASSWORD (kurly mints none), via envFrom.
  secretName='peertube-secrets',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    PEERTUBE_DB_HOSTNAME: dbHost,
    PEERTUBE_DB_PORT: '5432',
    PEERTUBE_DB_USERNAME: dbUser,
    PEERTUBE_DB_NAME: dbName,
    PEERTUBE_DB_SSL: 'false',
    PEERTUBE_REDIS_HOSTNAME: redisHost,
    PEERTUBE_REDIS_PORT: '6379',
    PEERTUBE_WEBSERVER_PORT: '443',
    PEERTUBE_WEBSERVER_HTTPS: 'true',
  } + (if webserverHost == null then {} else { PEERTUBE_WEBSERVER_HOSTNAME: webserverHost });

  // PeerTube keeps its config override at /config alongside its data at /data;
  // surface config as a subpath of the same volume so both persist.
  local configMount = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [{ name: 'store', mountPath: '/config', subPath: 'config' }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  // The image runs as uid 999; pin it and its fsGroup so the data volume is
  // writable and the restricted posture admits the pod.
  + kurly.runAs(999, gid=999, fsGroup=999)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '256Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + configMount
