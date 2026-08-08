// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// open-quartermaster — the Open QuarterMaster core API (the inventory management
// system's central service: items, storage blocks, checkouts and the labels that
// tie them together). A plain composable kurly.http workload on the official image,
// backed by an external MongoDB. Import it, point it at MongoDB, and render with
// kurly.list:
//
//   local oqm = import 'github.com/metio/kurly/workloads/open-quartermaster/server.libsonnet';
//   kurly.list(oqm(jwtKeyLocation='https://sso.example.com/realms/oqm/protocol/openid-connect/certs'))
//
// Serves the REST API on :8080 — compose an exposure onto it.
//
// DATABASE & SECRETS: the connection string carries the MongoDB credentials, so it
// lives in a Secret pulled in via envFrom; kurly authors none. Pairs with a
// mongodb-cluster named open-quartermaster-db.
//
// AUTHENTICATION: every write is behind a bearer token the API verifies against an
// OIDC provider's public keys (Keycloak upstream, with an `oqm` realm). jwtKeyLocation
// is that JWKS URL; kurly carries no identity provider for it. Left unset the API
// still starts and still refuses every authenticated call, which is the shape a smoke
// test sees and not a deployment anybody wants.
//
// The Quarkus runtime reads its HTTP port from QUARKUS_HTTP_PORT, which is set from
// the declared port rather than left to the image: the project's own compose file
// publishes :80 while the image's health check asks :8080, and a Service pointing at
// the wrong one of those is a workload that never goes ready.
//
// Stateless: items, attached files and audit history all live in MongoDB, so this is
// a plain rolling Deployment that scales freely.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='open-quartermaster',
  image=defaultImage,
  replicas=2,
  port=8080,
  // The MongoDB database the API stores everything in.
  database='oqm',
  // The OIDC provider's JWKS URL, whose keys bearer tokens are verified against.
  jwtKeyLocation=null,
  // Outgoing event messaging (Kafka). Off unless a broker is actually provided.
  events=false,
  // The Secret holding QUARKUS_MONGODB_CONNECTION_STRING (kurly mints none), via envFrom.
  secretName='open-quartermaster',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    {
      QUARKUS_HTTP_HOST: '0.0.0.0',
      QUARKUS_HTTP_PORT: std.toString(port),
      QUARKUS_MONGODB_DATABASE: database,
      MP_MESSAGING_OUTGOING_EVENTS_OUTGOING_ENABLED: if events then 'true' else 'false',
    }
    + (if jwtKeyLocation == null then {} else { SMALLRYE_JWT_VERIFY_KEY_LOCATION: jwtKeyLocation });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(185, gid=0, fsGroup=0)
  // The JVM writes its temporary files and its class-data archive under /tmp, which a
  // read-only root filesystem otherwise denies it before the application starts.
  + kurly.scratch('/tmp', '256Mi')
  // A JVM application that builds its Mongo indexes on first boot takes longer to
  // listen than a liveness delay should ever cover.
  + kurly.startupProbe({ httpGet: { path: '/q/health/started', port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/q/health/ready', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/q/health/live', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
