// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// rallly — a Rallly server (a self-hosted scheduling and group-poll tool for finding
// the best date to meet). A plain composable kurly.http workload on the official
// image, backed by an external PostgreSQL. Import it, point it at a database, and
// render with kurly.list:
//
//   local rallly = import 'github.com/metio/kurly/workloads/rallly/server.libsonnet';
//   kurly.list(rallly(baseUrl='https://rallly.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it. Being stateless
// (its state lives in the database), it can run several replicas.
//
// DATABASE & SECRETS: Rallly reads DATABASE_URL (with the database password embedded),
// SECRET_PASSWORD, and its SMTP credentials from the environment. kurly authors no
// Secret; provide one holding them, pulled in via envFrom. The defaults pair with a
// cnpg-cluster named rallly-db.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='rallly',
  image='ghcr.io/lukevella/rallly:4.11.1',
  // The public URL Rallly builds links against (required).
  baseUrl=null,
  // The Secret holding DATABASE_URL, SECRET_PASSWORD, and SMTP_* (kurly mints none),
  // via envFrom.
  secretName='rallly-secrets',
  replicas=1,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if baseUrl == null then {} else { NEXT_PUBLIC_BASE_URL: baseUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
