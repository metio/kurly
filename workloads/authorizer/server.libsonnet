// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// authorizer — an authentication server: sign-up and sign-in, social logins,
// multi-factor, and the OAuth2/OIDC endpoints applications point at. A plain
// composable kurly.http workload: every account and session lives in the external
// database, so it claims no volume. Import it and render with kurly.list:
//
//   local authorizer = import 'github.com/metio/kurly/workloads/authorizer/server.libsonnet';
//   kurly.list(authorizer(secretName='authorizer', appUrl='https://auth.example.com'))
//
// Serves the API, the login pages and the admin dashboard on :8080 — compose an
// exposure onto it.
//
// SECRETS REACH IT THROUGH A SHELL, AND THAT IS DELIBERATE. Authorizer v2 takes
// ALL of its configuration as command-line flags and reads no environment
// variables at all — its own words: "The server does not read from .env or OS
// environment variables." Writing the admin secret and the JWT secret straight
// into `args` would put both in the Deployment spec, readable by anything that
// can read Deployments. So the container runs `sh -c` and expands them from the
// Secret at startup, which is the pattern upstream documents for the same reason.
// They are still visible in the process's own argv inside this container; what
// this buys is keeping them out of the manifest and out of the API server.
//
// Stateless, so replicas scale — every one of them must carry the same
// jwt-secret, or a token minted by one is rejected by the next.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='authorizer',
  image=defaultImage,
  replicas=1,
  // postgres, mysql, sqlite, mongodb, arangodb, cassandradb, scylladb, dynamodb,
  // planetscale or couchbase.
  databaseType='postgres',
  // The URL a browser reaches this at; Authorizer builds its redirects from it.
  appUrl=null,
  // A Secret carrying DATABASE_URL, ADMIN_SECRET, JWT_SECRET, CLIENT_ID and
  // CLIENT_SECRET.
  secretName='authorizer',
  jwtType='HS256',
  // Appended to the command line verbatim, for the flags this stage does not
  // model. Do not put a credential here — see the header.
  extraArgs=[],
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.command(['sh', '-c'])
  + kurly.args([
    std.join(' ', [
      './authorizer',
      '--http-port=8080',
      '--database-type=' + databaseType,
      '--jwt-type=' + jwtType,
      '--database-url="$DATABASE_URL"',
      '--admin-secret="$ADMIN_SECRET"',
      '--jwt-secret="$JWT_SECRET"',
      '--client-id="$CLIENT_ID"',
      '--client-secret="$CLIENT_SECRET"',
    ] + (if appUrl != null then ['--app-url=' + appUrl] else []) + extraArgs),
  ])
  + kurly.env(env)
  + kurly.envFromSecret(secretName)
  // The uid the image's own authorizer user carries.
  + kurly.runAs(1000, gid=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
