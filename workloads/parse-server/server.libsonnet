// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// parse-server — a backend-as-a-service: a REST and GraphQL API over a document
// store, with users, sessions, files, push notifications and cloud functions. A
// plain composable kurly.http workload: all state is in the external database, so
// it claims no volume and scales horizontally. Import it and render with
// kurly.list:
//
//   local parse = import 'github.com/metio/kurly/workloads/parse-server/server.libsonnet';
//   kurly.list(parse(secretName='parse-server', serverUrl='https://api.example.com/parse'))
//
// Serves the API on :1337 under the /parse mount path — compose an exposure onto
// it.
//
// THE MASTER KEY IS THE WHOLE SECURITY MODEL. A request carrying it bypasses
// every class-level permission and ACL Parse enforces, so it belongs in the
// Secret `secretName` names, is never shipped to a client, and cannot be rotated
// without updating everything that holds it. The application id is not a secret
// and is set here.
//
// SERVER URL: `serverUrl` is the address Parse hands to clients and writes into
// the links in the files and password-reset mails it generates. It has to be the
// URL a client actually reaches, INCLUDING the mount path — a value that is right
// for the cluster and wrong for the internet produces working API calls and
// broken file downloads.
//
// FILES: the default file adapter writes into the database (GridFS on MongoDB),
// which is why this needs no volume. A deployment storing many large files wants
// an S3 file adapter configured through `env` instead.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='parse-server',
  image=defaultImage,
  replicas=1,
  // The application id clients send; not a secret.
  appId='parse',
  // The URL clients reach this at, mount path included.
  serverUrl='http://parse-server:1337/parse',
  // The path the API is served under.
  mountPath='/parse',
  // A Secret carrying PARSE_SERVER_MASTER_KEY and PARSE_SERVER_DATABASE_URI.
  secretName='parse-server',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(1337)
  + kurly.servicePort(1337)
  + kurly.env({
    PARSE_SERVER_APPLICATION_ID: appId,
    PARSE_SERVER_URL: serverUrl,
    PARSE_SERVER_MOUNT_PATH: mountPath,
    PORT: '1337',
  } + env)
  // The uid the image's own node user carries.
  + kurly.runAs(1000, gid=1000)
  // Uploads are buffered here before they reach the file adapter.
  + kurly.scratch('/tmp', '512Mi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ httpGet: { path: mountPath + '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: mountPath + '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
