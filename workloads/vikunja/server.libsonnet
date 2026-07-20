// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// vikunja — a Vikunja server (a self-hosted to-do and project-management app). A
// plain composable kurly.http workload on the official all-in-one image: it keeps
// its data in a SQLite database and its file attachments on a PersistentVolume by
// default, so it needs no external database. Import it and render with kurly.list:
//
//   local vikunja = import 'github.com/metio/kurly/workloads/vikunja/server.libsonnet';
//   kurly.list(vikunja(publicUrl='https://tasks.example.com'))
//
// Serves the web app and API on :3456 — compose an exposure onto it. Point
// VIKUNJA_DATABASE_TYPE at external PostgreSQL/MySQL through env to scale past the
// single SQLite writer.
//
// SECRETS: Vikunja reads VIKUNJA_SERVICE_JWTSECRET from the environment (keep it
// stable — sessions depend on it). kurly authors no Secret; provide one holding it,
// pulled in via envFrom.
//
// Single writer: the SQLite database and attachments live on a ReadWriteOnce volume,
// so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='vikunja',
  image='docker.io/vikunja/vikunja:v2.4.0',
  storageSize='2Gi',
  storageClass=null,
  // The public URL the frontend and API are reached at.
  publicUrl=null,
  // The Secret holding VIKUNJA_SERVICE_JWTSECRET (kurly mints none), via envFrom.
  secretName='vikunja-secrets',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    VIKUNJA_DATABASE_TYPE: 'sqlite',
    VIKUNJA_DATABASE_PATH: '/db/vikunja.db',
    VIKUNJA_FILES_BASEPATH: '/files',
    VIKUNJA_SERVICE_TIMEZONE: 'UTC',
  } + (if publicUrl == null then {} else { VIKUNJA_SERVICE_PUBLICURL: publicUrl });

  // Vikunja keeps its SQLite database and file attachments in two trees; surface
  // the files tree as a subpath of the same volume as the database.
  local files = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [{ name: 'store', mountPath: '/files', subPath: 'files' }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3456)
  + kurly.servicePort(3456)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/db', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/v1/info', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/v1/info', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + files
