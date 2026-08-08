// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// khoj — a Khoj server (searches your own documents and the web and answers
// questions from them). A composable kurly.http workload backed by an EXTERNAL
// PostgreSQL that must carry the PGVECTOR extension — the embeddings are stored
// and queried as vectors, so a plain PostgreSQL starts and then fails every
// search. Import it and render with kurly.list:
//
//   local khoj = import 'github.com/metio/kurly/workloads/khoj/server.libsonnet';
//   kurly.list(khoj())
//
// Serves the web app on :42110 — compose an exposure onto it.
//
// Two volumes, because the two directories hold different things: /root/.khoj is
// the configuration and the indexed content, /root/.cache the embedding models it
// downloads on first start. The cache is not state you must keep, but on an
// emptyDir every restart re-downloads gigabytes before the app answers anything.
//
// Django validates the Host header, so the probes here are CONNECTION probes: an
// HTTP probe from the kubelet arrives with the pod IP as its Host and Khoj answers
// 400 until KHOJ_DOMAIN names that too, which would kill the pod forever.
//
// Single writer: the index on a ReadWriteOnce volume, so one replica, recreated
// (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='khoj',
  image=defaultImage,
  // Configuration and the indexed content.
  storageSize='10Gi',
  // The embedding models, downloaded on first start.
  cacheSize='10Gi',
  storageClass=null,
  // The PostgreSQL it connects to — it must have pgvector available. The
  // non-secret coordinates are env; the passwords live in the Secret.
  dbHost='khoj-db-rw',
  dbPort=5432,
  database='khoj',
  dbUser='khoj',
  // The public host this instance is reached at. Django's ALLOWED_HOSTS and CSRF
  // origins are built from it, so a login through an exposure fails until it names
  // the host that exposure serves.
  domain=null,
  // The Secret holding POSTGRES_PASSWORD, KHOJ_DJANGO_SECRET_KEY, KHOJ_ADMIN_EMAIL
  // and KHOJ_ADMIN_PASSWORD. The admin pair creates the first Django superuser on
  // start; the Django key signs sessions, and it has a published default in the
  // project's own compose file.
  secretName='khoj',
  // Khoj serves anonymously when told to, which is how it is run without an
  // identity provider in front of it. Left off, accounts are required and are set
  // up through the Django admin.
  anonymousMode=false,
  args=null,
  env={},
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '6Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(42110)
  + kurly.servicePort(42110)
  + kurly.args(
    if args != null then args
    else [
      '--host=0.0.0.0',
      '--port=42110',
      '--non-interactive',
    ] + (if anonymousMode then ['--anonymous-mode'] else [])
  )
  + kurly.env(
    {
      POSTGRES_HOST: dbHost,
      POSTGRES_PORT: std.toString(dbPort),
      POSTGRES_DB: database,
      POSTGRES_USER: dbUser,
    }
    + (if domain == null then {} else { KHOJ_DOMAIN: domain })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image declares no user and the application writes into /root, so it runs as
  // root; capabilities stay dropped and privilege escalation stays off.
  + kurly.rootUser()
  // Python writes bytecode beside its own code under /app and /usr/local/lib.
  + kurly.writableRootFilesystem()
  + kurly.store('/root/.khoj', storageSize, storageClass=storageClass)
  + kurly.store('/root/.cache', cacheSize, storageClass=storageClass)
  // First start downloads the embedding models and runs the Django migrations
  // before it listens, which takes minutes on a cold cache.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
