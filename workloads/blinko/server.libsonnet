// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// blinko — a Blinko server (a self-hosted, AI-powered note-taking app for quickly
// capturing ideas). A plain composable kurly.http workload on the official image,
// backed by an external PostgreSQL, with its uploads on a PersistentVolume. Import
// it, point it at a database, and render with kurly.list:
//
//   local blinko = import 'github.com/metio/kurly/workloads/blinko/server.libsonnet';
//   kurly.list(blinko(nextauthUrl='https://notes.example.com'))
//
// Serves the web app and API on :1111 — compose an exposure onto it.
//
// DATABASE & SECRETS: Blinko reads DATABASE_URL (with the database password embedded)
// and NEXTAUTH_SECRET from the environment. kurly authors no Secret; provide one
// holding both, pulled in via envFrom. The defaults pair with a cnpg-cluster named
// blinko-db.
//
// Single writer: uploaded files live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='blinko',
  image='docker.io/blinkospace/blinko:1.8.8',
  storageSize='5Gi',
  storageClass=null,
  // The public URL (NextAuth needs it).
  nextauthUrl=null,
  // The Secret holding DATABASE_URL and NEXTAUTH_SECRET (kurly mints none), via
  // envFrom.
  secretName='blinko-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if nextauthUrl == null then {} else { NEXTAUTH_URL: nextauthUrl, NEXT_PUBLIC_BASE_URL: nextauthUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(1111)
  + kurly.servicePort(1111)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/.blinko', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
