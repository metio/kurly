// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// fider — a Fider server (an open-source platform to collect and prioritize customer
// feedback). A plain composable kurly.http workload on the official image, backed by
// an external PostgreSQL. Import it, point it at a database, and render with
// kurly.list:
//
//   local fider = import 'github.com/metio/kurly/workloads/fider/server.libsonnet';
//   kurly.list(fider(baseUrl='https://feedback.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it. Being stateless
// (its state lives in the database), it can run several replicas.
//
// DATABASE & SECRETS: Fider reads DATABASE_URL (with the database password embedded),
// JWT_SECRET, and its SMTP/email credentials from the environment. kurly authors no
// Secret; provide one holding them, pulled in via envFrom. The defaults pair with a
// cnpg-cluster named fider-db.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='fider',
  image='docker.io/getfider/fider:v0.36.0',
  // The public URL Fider builds links against (required).
  baseUrl=null,
  // The Secret holding DATABASE_URL, JWT_SECRET, and EMAIL_* (kurly mints none), via
  // envFrom.
  secretName='fider-secrets',
  replicas=1,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if baseUrl == null then {} else { BASE_URL: baseUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.readinessProbe({ httpGet: { path: '/_health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/_health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
