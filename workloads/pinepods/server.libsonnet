// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pinepods — a PinePods server (a podcast manager several people share: the
// subscriptions, the play positions and the downloads live in one database, so
// an episode paused on a phone resumes on a laptop). A composable kurly.http
// workload backed by an EXTERNAL PostgreSQL — the cnpg-cluster workload provides
// one — with downloaded episodes and backups on a PersistentVolume. Import it
// and render with kurly.list:
//
//   local pinepods = import 'github.com/metio/kurly/workloads/pinepods/server.libsonnet';
//   kurly.list(pinepods())
//
// Serves the web app on :8040 — compose an exposure onto it. nginx serves the
// compiled front end there and proxies /api to the FastAPI process on :8032,
// which is never exposed.
//
// The API reads PINEPODS_PORT as the port it tells clients to come back on, and
// the Service is named after the workload — so Kubernetes would inject
// PINEPODS_PORT as a tcp:// URL and every generated link would be unusable.
// Hence disableServiceLinks.
//
// It resolves podcast searches through the project's own API over the internet,
// so the pod needs egress even though nothing else here does; a NetworkPolicy
// composed onto it that forbids that leaves every search empty.
//
// Single writer: downloaded episodes on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='pinepods',
  image=defaultImage,
  // Downloaded episodes, backups and certificates.
  storageSize='20Gi',
  storageClass=null,
  // The PostgreSQL it connects to. The non-secret coordinates are env; the
  // password lives in the Secret. The database itself must exist — the start-up
  // script creates the schema and the first administrator in it, not the
  // database.
  dbHost='pinepods-db-rw',
  dbPort=5432,
  database='pinepods',
  dbUser='pinepods',
  // The host clients reach this instance on, which the API builds the links it
  // hands out from. Null leaves it to the container's own HOSTNAME, which here
  // is the pod name — every generated link then points at something only the
  // cluster can resolve.
  serverHost=null,
  // Set both when an exposure terminates TLS in front of this: the links the API
  // generates otherwise stay http:// and a browser refuses them on an https page.
  proxyProtocol='http',
  reverseProxy=false,
  // The podcast search service the project runs. Point it at your own if you
  // host one.
  searchApiUrl='https://api.pinepods.online/api/search',
  // The first administrator, created on the first start. The password is the
  // Secret's; leave it out and the container invents one and prints it to the
  // log, which is a credential anybody who can read logs then holds.
  adminFullname='Pinepods Admin',
  adminUsername='pine-admin',
  adminEmail='admin@pinepods.online',
  // The Secret holding DB_PASSWORD and PASSWORD.
  secretName='pinepods',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8040)
  + kurly.servicePort(8040)
  // PINEPODS_PORT is read by the API; the Service would inject it as a tcp://
  // URL and every link the API generates would carry that instead of a port.
  + kurly.disableServiceLinks()
  + kurly.env(
    {
      DB_TYPE: 'postgresql',
      DB_HOST: dbHost,
      DB_PORT: std.toString(dbPort),
      DB_NAME: database,
      DB_USER: dbUser,
      SEARCH_API_URL: searchApiUrl,
      PINEPODS_PORT: '8040',
      PROXY_PROTOCOL: proxyProtocol,
      REVERSE_PROXY: if reverseProxy then 'True' else 'False',
      FULLNAME: adminFullname,
      USERNAME: adminUsername,
      EMAIL: adminEmail,
    }
    + (if serverHost == null then {} else { HOSTNAME: serverHost })
    + env
  )
  + kurly.envFromSecret(secretName)
  // supervisord runs nginx, the API and cron together as root, and the start-up
  // script chowns the mail spool before any of them.
  + kurly.rootUser()
  + kurly.keepCapabilities()
  // nginx, supervisord and cron all keep their pid, spool and logs inside the
  // image's own tree, and the API caches beside its own code.
  + kurly.writableRootFilesystem()
  + kurly.store('/opt/pinepods', storageSize, storageClass=storageClass)
  // The first start waits for the database, creates the schema and builds the
  // first administrator before anything answers, so start-up is probed
  // separately from liveness.
  + kurly.startupProbe({ httpGet: { path: '/api/pinepods_check', port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/api/pinepods_check', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/pinepods_check', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
