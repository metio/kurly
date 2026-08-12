// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// superset/worker — the Celery worker behind Apache Superset: it runs the things
// the web server hands off rather than doing inline, which is asynchronous SQL Lab
// queries, alerts, reports and thumbnail generation. A composable kurly.worker
// workload (same image as the server, no Service). Import it and render alongside
// the server:
//
//   local server = import 'github.com/metio/kurly/workloads/superset/server.libsonnet';
//   local worker = import 'github.com/metio/kurly/workloads/superset/worker.libsonnet';
//   kurly.list([server(), worker()])
//
// WITHOUT ONE, THE FEATURES THAT NEED IT FAIL SILENTLY. A Superset with no worker
// still serves dashboards, and asynchronous queries simply queue forever, alerts
// never fire and reports never arrive — with nothing in the web server's log
// saying so. Deploy one, or turn those features off.
//
// SAME CONFIGURATION, SAME SECRET, SAME DATABASE. The worker executes queries on
// the same stored connections the server does, so it must read the identical
// superset_config.py and the identical SECRET_KEY — a worker with a different key
// cannot decrypt a single database password and every task fails.
//
// A worker also needs the celery BEAT scheduler for anything time-based (alerts,
// reports, cache warm-up); `beat` turns this stage into that scheduler instead.
// EXACTLY ONE beat may run: two schedulers double-fire every scheduled task.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './worker.image', '\n');

function(
  name='superset-worker',
  image=defaultImage,
  replicas=1,
  dbHost='superset-db-rw',
  dbPort=5432,
  dbName='superset',
  dbUser='superset',
  redisHost='superset-cache',
  redisPort=6379,
  // The same Secret the server reads.
  secretName='superset',
  // Run the celery beat scheduler instead of a worker. At most one.
  beat=false,
  // Celery worker concurrency; each slot runs one task.
  concurrency=4,
  extraConfig='',
  env={},
  resources={ requests: { cpu: '250m', memory: '1Gi' }, limits: { memory: '3Gi' } },
  labels={},
  annotations={},
)
  // The same configuration the server renders — kept identical on purpose, since
  // a worker whose settings differ decrypts nothing and reports no error worth
  // reading.
  local settings = |||
    import os
    from cachelib.redis import RedisCache

    SECRET_KEY = os.environ["SUPERSET_SECRET_KEY"]
    SQLALCHEMY_DATABASE_URI = (
        "postgresql+psycopg2://%(user)s:" + os.environ["DB_PASS"] + "@%(host)s:%(port)d/%(db)s"
    )

    REDIS_HOST = "%(redisHost)s"
    REDIS_PORT = %(redisPort)d

    CACHE_CONFIG = {
        "CACHE_TYPE": "RedisCache",
        "CACHE_DEFAULT_TIMEOUT": 300,
        "CACHE_KEY_PREFIX": "superset_",
        "CACHE_REDIS_HOST": REDIS_HOST,
        "CACHE_REDIS_PORT": REDIS_PORT,
        "CACHE_REDIS_DB": 1,
    }
    DATA_CACHE_CONFIG = CACHE_CONFIG
    FILTER_STATE_CACHE_CONFIG = CACHE_CONFIG
    EXPLORE_FORM_DATA_CACHE_CONFIG = CACHE_CONFIG

    class CeleryConfig:
        broker_url = f"redis://{REDIS_HOST}:{REDIS_PORT}/0"
        result_backend = f"redis://{REDIS_HOST}:{REDIS_PORT}/0"
        imports = ("superset.sql_lab", "superset.tasks.scheduler")
        worker_prefetch_multiplier = 1
        task_acks_late = True

    CELERY_CONFIG = CeleryConfig
    RESULTS_BACKEND = RedisCache(host=REDIS_HOST, port=REDIS_PORT, db=2, key_prefix="superset_results")
  ||| % { user: dbUser, host: dbHost, port: dbPort, db: dbName, redisHost: redisHost, redisPort: redisPort };

  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(if beat then 1 else replicas)
  + kurly.command(['celery'])
  + kurly.args(
    if beat then ['--app=superset.tasks.celery_app:app', 'beat', '--pidfile', '/tmp/celerybeat.pid']
    else ['--app=superset.tasks.celery_app:app', 'worker', '--pool=prefork', '--concurrency=' + concurrency, '-Ofair']
  )
  + kurly.env({
    SUPERSET_CONFIG_PATH: '/app/pythonpath/superset_config.py',
    PYTHONPATH: '/app/pythonpath:/app',
    SUPERSET_HOME: '/app/superset_home',
  } + env)
  // The uid the image's own superset user carries.
  + kurly.runAs(1000, gid=1000)
  + kurly.scratch('/tmp', '2Gi')
  + kurly.scratch('/app/superset_home', '1Gi')
  + kurly.envFromSecret(secretName)
  + kurly.config({ 'superset_config.py': settings + extraConfig }, mountPath='/app/pythonpath')
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
