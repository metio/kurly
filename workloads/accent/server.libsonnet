// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// accent — an Accent server (a translation and localisation tool for developers:
// it reads the translation files out of a repository, gives translators a web app
// to work in, and writes the files back). A plain composable kurly.http workload on
// the official image, backed by an external PostgreSQL — the cnpg-cluster workload
// provides one. Import it, point it at a database, and render with kurly.list:
//
//   local accent = import 'github.com/metio/kurly/workloads/accent/server.libsonnet';
//   kurly.list(accent())
//
// Serves the web app and API on :4000 — compose an exposure onto it. All state is
// in PostgreSQL, so this stage claims no volume and can run several replicas.
//
// DATABASE & SECRETS: Accent reads DATABASE_URL and SECRET_KEY_BASE from the
// environment. kurly authors no Secret; provide one holding both (the database
// password is embedded in DATABASE_URL) and it is pulled in via envFrom.
// SECRET_KEY_BASE signs the session cookie, so a value that changes on every
// restart signs everybody out. The defaults pair with a cnpg-cluster named
// accent-db.
//
// AUTHENTICATION: Accent signs users in through an external provider (GitHub,
// GitLab, Google, Slack, Discord) configured by provider-specific env, or with
// DUMMY_LOGIN_ENABLED=true, which accepts an email address and no password. With
// neither set, nobody can sign in — so choose one before exposing it, and never
// leave the dummy login reachable from outside the cluster.
//
// The release migrates the database on start, so the first boot of a fresh
// database is slower than the ones after it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='accent',
  image=defaultImage,
  // The Secret holding DATABASE_URL and SECRET_KEY_BASE (kurly mints none),
  // pulled into the environment via envFrom.
  secretName='accent',
  // The URL the browser reaches this instance at. Accent builds the links it puts
  // in its web app and its emails from it, so a wrong value renders a UI whose
  // links go somewhere else. There is no default that is right anywhere.
  canonicalUrl=null,
  replicas=1,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(4000)
  + kurly.servicePort(4000)
  + kurly.envFromSecret(secretName)
  + kurly.env(
    {
      PORT: '4000',
      // An Elixir release writes its runtime vm.args and its cookie into the
      // release tree unless RELEASE_TMP names somewhere else; the root filesystem
      // is read-only here, so name the scratch.
      RELEASE_TMP: '/tmp',
    }
    + (if canonicalUrl == null then {} else { CANONICAL_URL: canonicalUrl })
    + env
  )
  // The image's USER is the NAME `nobody`, which kubelet cannot check against
  // runAsNonRoot — it refuses to start a container whose user is non-numeric — so
  // pin the uid Debian gives that account. The release tree is chowned
  // nobody:root, so the group stays 0 and is left alone.
  + kurly.runAs(65534)
  + kurly.scratch('/tmp', '256Mi')
  // The BEAM boots and the release runs the database migrations before it
  // listens; a liveness probe alone would restart it mid-migration.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
