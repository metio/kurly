// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// discount-bandit — a Discount Bandit server (tracks the price and stock of products
// across Amazon, eBay, AliExpress and custom stores, and notifies when a price meets
// the criteria a user set). A plain composable kurly.http workload on the official
// image, backed by an external MySQL/MariaDB. Import it, point it at a database, and
// render with kurly.list:
//
//   local bandit = import 'github.com/metio/kurly/workloads/discount-bandit/server.libsonnet';
//   kurly.list(bandit(appUrl='https://prices.example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: the image ships SQLite as Laravel's default and creates no
// database file, so this stage runs it on MySQL/MariaDB instead — the mysql-cluster
// workload provides one. It reads its database coordinates from env and DB_PASSWORD
// and APP_KEY from a provided Secret via envFrom. APP_KEY is Laravel's encryption
// key: a 32-character string, and everything encrypted with the previous one is
// unreadable once it changes. kurly authors no Secret.
//
// FRANKEN_HOST is set to 0.0.0.0. The image bakes `localhost`, which Octane passes
// to FrankenPHP as its listen address, so the default binds the loopback interface
// only and every request through the Service is refused by a pod that looks healthy.
//
// Everything else the container does happens in its own tree: the entrypoint copies
// .env into /app, links storage, runs the migrations and writes Laravel's compiled
// caches back beside the code, then supervisord runs Octane, the scheduler and the
// queue worker as root. Hence root and a writable root filesystem, with all
// capabilities dropped and no privilege escalation.
//
// The first start migrates and seeds the database, warms the Filament and Laravel
// caches and installs Octane before anything listens, so it carries a startup probe
// rather than a stretched liveness delay.
//
// Single scheduler: the pod runs the cron scheduler and the queue worker alongside
// the web server, so a second replica would scrape every tracked product twice —
// one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='discount-bandit',
  image=defaultImage,
  dbHost='discount-bandit-db',
  dbPort=3306,
  dbName='discount-bandit',
  dbUser='discount-bandit',
  // The public URL Discount Bandit builds links and assets against (required).
  appUrl=null,
  // How often the scheduler re-checks every tracked product.
  cron='*/5 * * * *',
  timezone='UTC',
  // The Secret holding DB_PASSWORD and APP_KEY (kurly mints none), via envFrom.
  secretName='discount-bandit',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_CONNECTION: 'mysql',
    DB_HOST: dbHost,
    DB_PORT: std.toString(dbPort),
    DB_DATABASE: dbName,
    DB_USERNAME: dbUser,
    APP_TIMEZONE: timezone,
    CRON: cron,
    FRANKEN_HOST: '0.0.0.0',
  } + (if appUrl == null then {} else { APP_URL: appUrl, ASSET_URL: appUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  // Laravel reads any environment variable as configuration, so the <APP>_PORT
  // link variables Kubernetes injects can be read as settings; the app needs
  // none of them.
  + kurly.disableServiceLinks()
  + kurly.rootUser()
  // Everything is dropped and this one is granted back by name: the frankenphp
  // binary Octane runs carries cap_net_bind_service as a file capability, and
  // no_new_privs makes executing such a binary fail outright — supervisord
  // restarts it until it gives up, and the pod never listens.
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  + kurly.allowPrivilegeEscalation()
  + kurly.writableRootFilesystem()
  // Octane serves the app but validates the Host header on the routes it answers,
  // so probe by connection.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
