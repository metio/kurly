// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ente museum — the server behind Ente, a self-hosted, end-to-end-encrypted
// photo and video backup (the Google Photos alternative). Museum is a stateless
// Go API on :8080: it keeps its metadata in PostgreSQL and the encrypted blobs
// in S3-compatible object storage, so the workload itself needs no volume. The
// Ente clients (mobile, desktop, web) point at this API.
//
//   local museum = import 'github.com/metio/kurly/workloads/ente/server.libsonnet';
//   kurly.list(museum())
//
// Museum reads its base config from configurations/local.yaml baked into the
// image and merges the operator's credentials file — the PostgreSQL DSN, the S3
// endpoint/bucket/keys, and the app secrets (key.encryption, key.hash,
// jwt.secret). kurly authors NO Secret: supply that credentials.yaml as a Secret
// and point ENTE_CREDENTIALS_FILE at it (the default below). Every config value
// can also be overridden by an ENTE_-prefixed env var (db.host -> ENTE_DB_HOST).
//
// Stateless (state lives in PostgreSQL and S3), so scale it by replicas — after
// the first start, which runs the schema migrations under a lock a second
// instance would race for.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='ente-server',
  // Museum publishes only commit-tagged and moving tags, so it is pinned as
  // latest@digest — a known artifact that Renovate refreshes.
  image=defaultImage,
  // Museum runs its schema migrations on every start, and two instances starting
  // together race for the migration lock — so it starts single and is scaled up
  // once the schema is in place.
  replicas=1,
  credentialsSecret='ente',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.runAs(1000, gid=1000)
  // Museum writes only ephemeral scratch (its state is in PostgreSQL and S3), so
  // the restricted read-only root filesystem holds with a writable /tmp.
  + kurly.scratch('/tmp', '128Mi')
  // The credentials file (db + s3 + app secrets) the operator supplies as a
  // Secret with a credentials.yaml key.
  + kurly.secretMount(credentialsSecret, '/credentials')
  + kurly.env({ ENTE_CREDENTIALS_FILE: '/credentials/credentials.yaml' } + env)
  + kurly.readinessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
