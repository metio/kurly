// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// bitcart — a Bitcart merchants API server (the backend of the self-hosted
// cryptocurrency payment processor: stores, invoices, wallets and the admin API),
// backed by an external PostgreSQL and Redis. A composable kurly.http workload on
// the official backend image. Import it, point it at its backends, and render with
// kurly.list:
//
//   local bitcart = import 'github.com/metio/kurly/workloads/bitcart/server.libsonnet';
//   kurly.list(bitcart(apiHost='api.example.com', adminHost='admin.example.com'))
//
// Serves the API on :8000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: the PostgreSQL and Redis connection settings are env, from the
// dbHost/dbName/dbUser/redisHost parameters (defaults pair with a cnpg-cluster named
// bitcart-db and a valkey named bitcart-cache). The Secret holds only DB_PASSWORD,
// pulled in via envFrom; kurly authors no Secret.
//
// SCHEMA MIGRATIONS run in the container's own command, before gunicorn: the image
// ships alembic and the compose deployment upgrades the schema on every start, so
// the first boot takes minutes and needs the startup probe rather than a longer
// liveness delay.
//
// ROOT AND A WRITABLE ROOT FILESYSTEM: the image's entrypoint runs as root — it adds
// a group, chowns $BITCART_VOLUMES, and only then drops to the electrum account with
// gosu — so the restricted defaults are relaxed exactly as far as that needs
// (rootUser + allowPrivilegeEscalation + keepCapabilities, and a writable root
// filesystem for the /etc writes groupadd makes).
//
// OUTBOUND HTTPS: the API fetches the plugin schema from bitcart.ai at startup and
// does not catch a failure, so a cluster that blocks egress keeps it from booting.
//
// The datadir holds uploaded images, plugin trees and backups, and its defaults sit
// beside the application's own code — everything is pointed at one PersistentVolume
// instead. That volume is ReadWriteOnce, so this is one replica, recreated (never
// rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='bitcart',
  image=defaultImage,
  // The public host:port the API and the admin front end are reached at. Bitcart
  // builds absolute links from them; the defaults keep a default render bootable.
  apiHost='localhost:8000',
  adminHost='localhost:3000',
  // The coins to enable, as the comma-separated list BITCART_CRYPTOS takes. Each
  // one needs its own coin daemon reachable from this pod.
  cryptos='btc',
  // gunicorn's own config defaults to 2 x CPU count + 1 uvicorn workers — read off
  // the NODE, not off the container's limits, so a big node spawns dozens inside a
  // 1Gi container and the pod is killed for memory it never asked for.
  workers=4,
  storageSize='5Gi',
  storageClass=null,
  // The PostgreSQL and Redis the server connects to. The non-secret connection
  // settings are env; the password lives in the Secret (DB_PASSWORD), via envFrom.
  dbHost='bitcart-db-rw',
  dbName='bitcart',
  dbUser='bitcart',
  redisHost='bitcart-cache-headless',
  // The Secret holding DB_PASSWORD (kurly mints none), via envFrom.
  secretName='bitcart',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    BITCART_CRYPTOS: cryptos,
    BITCART_API_WORKERS: std.toString(workers),
    BITCART_HOST: apiHost,
    BITCART_ADMIN_HOST: adminHost,
    // Every path Bitcart writes to defaults to a directory inside its own install
    // tree (`data`, `modules`), which a read-only /app cannot take and a restart
    // would discard anyway. They are moved onto the volume, one directory each.
    BITCART_DATADIR: '/datadir',
    BITCART_BACKUPS_DIR: '/datadir/backups',
    BITCART_BACKEND_PLUGINS_DIR: '/datadir/backend_plugins',
    BITCART_ADMIN_PLUGINS_DIR: '/datadir/admin_plugins',
    BITCART_STORE_PLUGINS_DIR: '/datadir/store_plugins',
    BITCART_DAEMON_PLUGINS_DIR: '/datadir/daemon_plugins',
    BITCART_DOCKER_PLUGINS_DIR: '/datadir/docker_plugins',
    // What the entrypoint chowns to the electrum account before dropping to it.
    BITCART_VOLUMES: '/datadir',
    DB_HOST: dbHost,
    DB_PORT: '5432',
    DB_DATABASE: dbName,
    DB_USER: dbUser,
    REDIS_HOST: 'redis://' + redisHost + ':6379',
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  // The image runs gunicorn from its own config (0.0.0.0:8000), after upgrading the
  // database schema — the compose deployment does the same, and the API itself
  // never migrates.
  + kurly.args(['sh', '-c', 'alembic upgrade head && exec gunicorn -c gunicorn.conf.py main:app'])
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  // A Service named after the workload would inject BITCART_PORT as a tcp:// URL
  // into a container whose whole configuration is read from BITCART_-prefixed env.
  + kurly.disableServiceLinks()
  // The entrypoint adds a group and chowns the volume before gosu drops it to the
  // electrum account, so it needs root, the escalation gosu's setuid bit performs,
  // and the capabilities to change ownership and identity.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/datadir', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '256Mi')
  // Probe by connection: / is a ReDoc page and every API route below it answers 401
  // without a token, so an httpGet probe would either follow documentation or fail
  // authentication forever.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
