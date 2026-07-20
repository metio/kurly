// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// documenso — a Documenso server (a self-hosted, open-source alternative to DocuSign for signing
// documents). A plain composable kurly.http workload on the official image, backed by an external
// PostgreSQL. Import it, point it at its backends, and render with kurly.list:
//
//   local documenso = import 'github.com/metio/kurly/workloads/documenso/server.libsonnet';
//   kurly.list(documenso(webappUrl='https://sign.example.com'))
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Documenso reads NEXTAUTH_URL, NEXTAUTH_SECRET,
// NEXT_PRIVATE_ENCRYPTION_KEY, NEXT_PRIVATE_ENCRYPTION_SECONDARY_KEY, NEXT_PRIVATE_DATABASE_URL
// and its SMTP settings from the environment. kurly authors no Secret; provide one holding them,
// via envFrom. The defaults pair with a cnpg-cluster named documenso-db.
//
// Stateless: a plain rolling Deployment. Signed documents are stored in the database (or in S3
// when NEXT_PRIVATE_UPLOAD_TRANSPORT=s3 is set in the Secret).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='documenso',
  image='docker.io/documenso/documenso:latest@sha256:cd38a43c050fd14435653c0f66faf8dad538de8ebb7a072c72fb0ab6371d770f',
  replicas=2,
  webappUrl=null,
  secretName='documenso-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if webappUrl == null then {} else { NEXTAUTH_URL: webappUrl, NEXT_PUBLIC_WEBAPP_URL: webappUrl };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
