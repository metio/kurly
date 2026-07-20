// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mattermost — a Mattermost server (a self-hosted, open-source team messaging platform:
// channels, threads, and integrations, à la Slack). A plain composable kurly.http
// workload on the Team Edition image, backed by an external PostgreSQL, with its file
// uploads on a PersistentVolume. Import it, point it at a database, and render with
// kurly.list:
//
//   local mattermost = import 'github.com/metio/kurly/workloads/mattermost/server.libsonnet';
//   kurly.list(mattermost(siteUrl='https://chat.example.com'))
//
// Serves the web app and API on :8065 — compose an exposure onto it.
//
// DATABASE & SECRETS: Mattermost reads its database DSN from MM_SQLSETTINGS_DATASOURCE.
// kurly authors no Secret; provide one holding it, pulled in via envFrom. The defaults
// pair with a cnpg-cluster named mattermost-db.
//
// Single writer: uploaded files live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files. Point the file store at S3
// (MM_FILESETTINGS_DRIVERNAME=amazons3) to run more than one replica.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='mattermost',
  image='docker.io/mattermost/mattermost-team-edition:11.8.4',
  storageSize='20Gi',
  storageClass=null,
  // The public URL (Mattermost builds absolute links and validates it).
  siteUrl=null,
  // The Secret holding MM_SQLSETTINGS_DATASOURCE (kurly mints none), via envFrom.
  secretName='mattermost-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { MM_SQLSETTINGS_DRIVERNAME: 'postgres' }
    + (if siteUrl == null then {} else { MM_SERVICESETTINGS_SITEURL: siteUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8065)
  + kurly.servicePort(8065)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  // The image runs as the 'mattermost' user (uid 2000); pin it so the restricted
  // posture admits it and the mounted volume is owned correctly.
  + kurly.runAs(2000, gid=2000, fsGroup=2000)
  + kurly.writableRootFilesystem()
  + kurly.store('/mattermost/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/v4/system/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/v4/system/ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
