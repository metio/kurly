// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// budget-board/server — the Budget Board API (tracks monthly spending, budgets
// and progress towards financial goals). A composable kurly.http workload backed
// by an EXTERNAL PostgreSQL — the cnpg-cluster workload provides one — holding
// every piece of state, so the pod itself is stateless. Import it and render with
// kurly.list:
//
//   local server = import 'github.com/metio/kurly/workloads/budget-board/server.libsonnet';
//   kurly.list(server())
//
// Serves the API on :8080. The browser talks to the client stage, which proxies
// /api/ here — compose an exposure onto the CLIENT, not onto this.
//
// clientAddress is the browser-visible origin of the client and is the one value
// that cannot have a sensible default: the API refuses to start without it (it is
// the sole CORS origin), and a wrong value leaves every request from the browser
// blocked by the browser rather than by the server.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='budget-board-server',
  image=defaultImage,
  replicas=1,
  // The origin the browser loads the client from. Sent verbatim as the allowed
  // CORS origin, so it is a URL with a scheme, not a hostname.
  clientAddress='http://budget-board-client:6253',
  // The PostgreSQL it connects to. The non-secret coordinates are env; the
  // password lives in the Secret.
  dbHost='budget-board-db-rw',
  dbPort=5432,
  database='budgetboard',
  dbUser='budgetboard',
  // The Secret holding POSTGRES_PASSWORD. The project's own compose file ships a
  // published default for it, so supplying one is not hardening — it is the
  // difference between the database being reachable by anybody and not.
  secretName='budget-board',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    {
      CLIENT_ADDRESS: clientAddress,
      POSTGRES_HOST: dbHost,
      POSTGRES_PORT: std.toString(dbPort),
      POSTGRES_DATABASE: database,
      POSTGRES_USER: dbUser,
      // The schema is migrated by the application on start; without it a fresh
      // database has no tables and every request fails.
      AUTO_UPDATE_DB: 'true',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The image declares no user and the .NET base image publishes the account it
  // was built for as APP_UID=1654; /app is world-readable, so it runs as that.
  + kurly.runAs(1654, gid=1654, fsGroup=1654)
  // ASP.NET writes its data-protection keys under $HOME and unpacks temporary
  // files under /tmp; scratches there keep the root filesystem read-only. The
  // keys are per-pod and per-restart, so a restart signs out everybody who is
  // logged in — the alternative is a volume, which would pin the API to one node
  // for state PostgreSQL already holds.
  + kurly.scratch('/home/app/.aspnet', '16Mi')
  + kurly.scratch('/tmp', '64Mi')
  // No health endpoint is served: every route is either the identity API or a
  // controller behind authentication, so probing by path answers 401 or 404.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
