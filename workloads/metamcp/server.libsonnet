// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// metamcp — an MCP proxy: it aggregates several Model Context Protocol servers
// into one endpoint, groups them into namespaces and applies middleware in front,
// so a client holds one URL instead of a list that changes. A plain composable
// kurly.http workload backed by an external PostgreSQL. Import it and render with
// kurly.list:
//
//   local metamcp = import 'github.com/metio/kurly/workloads/metamcp/server.libsonnet';
//   kurly.list(metamcp(appUrl='https://mcp.example.com'))
//
// Serves the interface and the aggregated endpoint on :12008 — compose an
// exposure onto it.
//
// APP_URL IS REQUIRED AND IT IS NOT DECORATION. The application throws
// "APP_URL environment variable is required" and exits without one, and it
// builds its callback URLs from it and validates request origins against it — so
// a wrong value gives a page that loads and a login that fails. The default here
// is a placeholder that boots and is wrong for every real deployment: set it to
// the URL a browser actually uses.
//
// THE FIRST ACCOUNT IS CREATED BY WHOEVER GETS THERE FIRST unless you bootstrap
// one. Registration is open until an administrator exists; `bootstrapEmail` and
// the matching Secret keys create that account at start instead, which is the
// difference between an instance you own and an instance the internet owns.
//
// Stateless: everything is in PostgreSQL, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='metamcp',
  image=defaultImage,
  replicas=1,
  dbHost='metamcp-db-rw',
  dbPort=5432,
  dbName='metamcp',
  dbUser='metamcp',
  // The URL a browser reaches this at. Callback URLs and origin checks are built
  // from it, and the application refuses to start without one — so this defaults
  // to a placeholder that boots rather than to null, which would not.
  appUrl='http://localhost:12008',
  // The account created at start, so registration is not left open to whoever
  // arrives first. Its password comes from the Secret.
  bootstrapEmail=null,
  bootstrapName='admin',
  logLevel='info',
  // A Secret carrying DATABASE_URL (the whole connection string, which the
  // migration step reads), POSTGRES_PASSWORD, BETTER_AUTH_SECRET and — when
  // bootstrapEmail is set — BOOTSTRAP_USER_PASSWORD. DATABASE_URL is in the
  // Secret rather than composed here because Kubernetes expands $(VAR) only from
  // the container's own env list, never from an envFrom source.
  secretName='metamcp',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(12008)
  + kurly.servicePort(12008)
  + kurly.env(
    {
      // HOME, because the migration step runs pnpm and pnpm writes a tool cache
      // under it — unset, it resolves to / and the migration fails with ENOENT
      // before the application has started once.
      HOME: '/tmp',
      NODE_ENV: 'production',
      LOG_LEVEL: logLevel,
      POSTGRES_HOST: dbHost,
      POSTGRES_PORT: std.toString(dbPort),
      POSTGRES_DB: dbName,
      POSTGRES_USER: dbUser,
    }
    + { APP_URL: appUrl, NEXT_PUBLIC_APP_URL: appUrl }
    + (
      if bootstrapEmail != null
      then {
        BOOTSTRAP_ENABLE: 'true',
        BOOTSTRAP_USER_EMAIL: bootstrapEmail,
        BOOTSTRAP_USER_NAME: bootstrapName,
        BOOTSTRAP_ONLY_FIRST_RUN: 'true',
      }
      else {}
    )
    + env
  )
  + kurly.envFromSecret(secretName)
  // The uid the image's own nextjs user carries.
  + kurly.runAs(1000, gid=1000)
  // Next.js writes its build cache and the proxy buffers responses.
  + kurly.scratch('/tmp', '512Mi')
  + kurly.scratch('/app/.next/cache', '512Mi')
  // The first start applies database migrations before it listens.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
