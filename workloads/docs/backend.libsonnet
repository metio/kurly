// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docs/backend — the Django API behind Docs, the collaborative note-taking and
// wiki tool incubated by France's DINUM and now a Digital Public Good. A
// composable kurly.http workload: documents, permissions and accounts live in an
// external PostgreSQL, attachments in object storage. Import it and render
// alongside the other two stages:
//
//   local backend = import 'github.com/metio/kurly/workloads/docs/backend.libsonnet';
//   local frontend = import 'github.com/metio/kurly/workloads/docs/frontend.libsonnet';
//   local yprovider = import 'github.com/metio/kurly/workloads/docs/y-provider.libsonnet';
//   kurly.list([backend(), frontend(), yprovider()])
//
// Serves the API on :8000.
//
// THREE PIECES, AND EACH ONE MATTERS. The frontend serves the application, this
// backend answers it, and y-provider carries the live collaborative editing — a
// deployment missing y-provider looks like it works until two people open the
// same document and neither sees the other's typing.
//
// SIGN-IN GOES THROUGH AN EXTERNAL PROVIDER. Docs authenticates over OIDC and has
// no local accounts, so without a provider configured nobody can sign in at all.
// `secretName` carries the client credentials along with DJANGO_SECRET_KEY, which
// signs the session cookie — a value that changes on restart signs everybody out.
//
// ATTACHMENTS GO TO OBJECT STORAGE, not to a volume, which is why this claims
// none. kurly carries seaweedfs, garagehq and zenko-cloudserver for that.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './backend.image', '\n');

function(
  name='docs-backend',
  image=defaultImage,
  replicas=1,
  dbHost='docs-db-rw',
  dbPort=5432,
  dbName='docs',
  dbUser='docs',
  redisHost='docs-cache',
  redisPort=6379,
  // The origin a browser reaches Docs at; the links and OIDC redirects are built
  // from it.
  publicUrl=null,
  // A Secret carrying DJANGO_SECRET_KEY, DB_PASSWORD, the OIDC client credentials
  // and the object-storage keys.
  secretName='docs',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(
    {
      DJANGO_SETTINGS_MODULE: 'impress.settings',
      DJANGO_CONFIGURATION: 'Production',
      DB_HOST: dbHost,
      DB_PORT: std.toString(dbPort),
      DB_NAME: dbName,
      DB_USER: dbUser,
      REDIS_URL: 'redis://' + redisHost + ':' + redisPort + '/1',
    }
    + (if publicUrl != null then { DJANGO_ALLOWED_HOSTS: publicUrl, DJANGO_CSRF_TRUSTED_ORIGINS: publicUrl } else {})
    + env
  )
  + kurly.envFromSecret(secretName)
  // The uid and gid the image already runs as.
  + kurly.runAs(1001, gid=127)
  + kurly.scratch('/tmp', '512Mi')
  + kurly.scratch('/data/media', '1Gi')
  + kurly.scratch('/data/static', '512Mi')
  // BY CONNECTION, NOT BY REQUEST. The backend answers every plaintext request
  // with a 301 to the same URL over HTTPS — correct for an application that
  // expects TLS to be terminated in front of it, and fatal as a probe: the
  // kubelet follows the redirect, speaks TLS to a plaintext listener, and marks a
  // healthy pod unready forever.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
