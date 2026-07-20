// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// linkwarden — a Linkwarden server (a self-hosted bookmark manager that archives a
// copy of every page). A plain composable kurly.http workload on the official
// image, backed by an external PostgreSQL, with its archived pages on a
// PersistentVolume. Import it, point it at a database, and render with kurly.list:
//
//   local linkwarden = import 'github.com/metio/kurly/workloads/linkwarden/server.libsonnet';
//   kurly.list(linkwarden(nextauthUrl='https://links.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// DATABASE & SECRETS: Linkwarden reads DATABASE_URL (with the database password
// embedded) and NEXTAUTH_SECRET from the environment. kurly authors no Secret;
// provide one holding both, pulled in via envFrom. The defaults pair with a
// cnpg-cluster named linkwarden-db.
//
// Single writer: with local storage, archived pages live on a ReadWriteOnce volume,
// so one replica, recreated. Move to S3 (the seaweedfs workload) to scale out.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='linkwarden',
  image='ghcr.io/linkwarden/linkwarden:v2.15.1',
  storageSize='10Gi',
  storageClass=null,
  // The public URL (NextAuth needs it).
  nextauthUrl=null,
  // The Secret holding DATABASE_URL and NEXTAUTH_SECRET (kurly mints none), via
  // envFrom.
  secretName='linkwarden-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    NEXTAUTH_URL: (if nextauthUrl == null then 'http://localhost:3000/api/v1/auth' else nextauthUrl + '/api/v1/auth'),
  } + (if nextauthUrl == null then {} else { NEXT_PUBLIC_LINKWARDEN_URL: nextauthUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/data/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
