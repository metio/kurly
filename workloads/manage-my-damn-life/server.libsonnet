// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// manage-my-damn-life — an MMDL server (a web front end for the CalDAV servers
// you already run: tasks and calendars from several accounts in one place, with
// labels, filters and reminders). A composable kurly.http workload backed by an
// EXTERNAL database — the cnpg-cluster workload provides a PostgreSQL — and
// nothing else: it keeps no files of its own, so it claims no volume. Import it
// and render with kurly.list:
//
//   local mmdl = import 'github.com/metio/kurly/workloads/manage-my-damn-life/server.libsonnet';
//   kurly.list(mmdl())
//
// Serves the web application on :3000 — compose an exposure onto it.
//
// THE FIRST VISIT GOES TO /install, and that is what creates the schema: the
// image starts the Next.js server directly and migrates nothing on boot, so a
// fresh database is an application that answers but has no tables until somebody
// walks that page. Probing by connection rather than by path is what keeps a
// pod alive long enough for them to do it.
//
// SET `baseUrl` TO THE URL PEOPLE WILL VISIT. It is what the application builds
// absolute links from, and what NextAuth compares a callback against when third
// party sign-in is switched on.
//
// The database it talks to is chosen by `dbDialect` — postgres, mysql or
// sqlite — because MMDL speaks all three and the port that follows differs;
// postgres pairs with a cnpg-cluster named <name>-db.
//
// Stateless as far as the cluster is concerned: everything durable is in the
// database, so replicas are a decision for the caller rather than a thing the
// storage forbids.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='manage-my-damn-life',
  image=defaultImage,
  // The database it stores accounts, labels and filters in. The password lives
  // in the Secret; these are the coordinates around it.
  dbDialect='postgres',
  dbHost='manage-my-damn-life-db-rw',
  dbPort=5432,
  dbName='mmdl',
  dbUser='mmdl',
  // The public URL a browser reaches this instance at. Absent by default,
  // because a wrong one is worse than none.
  baseUrl=null,
  // The Secret holding DB_PASS and AES_PASSWORD. AES_PASSWORD encrypts the
  // CalDAV passwords the application stores on a user's behalf, so changing it
  // later makes every stored account unreadable rather than merely re-encrypted.
  secretName='manage-my-damn-life',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
                    DB_DIALECT: dbDialect,
                    DB_HOST: dbHost,
                    DB_PORT: std.toString(dbPort),
                    DB_NAME: dbName,
                    DB_USER: dbUser,
                    // The image's own flag for "this is the container build", which
                    // is how it resolves the paths its migrations live under.
                    DOCKER_INSTALL: 'true',
                  }
                  + (if baseUrl == null then {} else { NEXT_BASE_URL: baseUrl, NEXTAUTH_URL: baseUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  // A Service named after the workload injects <NAME>_PORT as a tcp:// URL, and
  // Node reads PORT-shaped variables out of the environment it is handed.
  + kurly.disableServiceLinks()
  // The image builds and chowns its tree to the nextjs account it creates
  // (1001:1001) and starts the server as that account, dropping nothing, so the
  // hardened posture stands as it is.
  + kurly.runAs(1001, gid=1001)
  // Next.js writes its incremental render cache inside its own tree, and the
  // standalone server keeps temporary files in /tmp; the root filesystem stays
  // read-only.
  + kurly.scratch('/app/.next/cache')
  + kurly.scratch('/tmp')
  // Probed by connection: every path answers with a redirect to /install or to
  // the login page depending on how far setup has got, and a probe that follows
  // one would kill the pod exactly when somebody is installing it.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
