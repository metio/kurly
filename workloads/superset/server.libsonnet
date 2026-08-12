// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// superset — Apache Superset: a business-intelligence web application for
// exploring databases, building charts and assembling dashboards. A composable
// kurly.http workload holding no state of its own: metadata goes to an external
// PostgreSQL and the query cache and async results to Redis. Import it and render
// with kurly.list:
//
//   local superset = import 'github.com/metio/kurly/workloads/superset/server.libsonnet';
//   kurly.list(superset())
//
// Serves the web UI and API on :8088 — compose an exposure onto it. The worker
// stage belongs beside it for anything that runs asynchronously.
//
// THE SECRET KEY ENCRYPTS EVERY STORED DATABASE PASSWORD. Superset keeps the
// credentials of the databases it queries in its metadata database, encrypted
// with SECRET_KEY. A key that changes makes every one of those connections
// unreadable, and Superset refuses to start rather than pretend otherwise — so it
// comes from the Secret `secretName` names and stays put. Rotating it is a
// documented Superset procedure, not an edit here.
//
// IT MIGRATES ITSELF BEFORE IT SERVES. An init container runs `superset db
// upgrade` and `superset init` against the metadata database. Both are
// idempotent, which is what lets a fresh deployment come up without a manual
// step. The first run on an empty database takes minutes, which is why the
// startup probe's budget is long: a shorter one restarts the pod mid-migration
// and the next attempt starts over.
//
// Stateless, so replicas scale — but they share one metadata database and one
// Redis, and every replica must carry the same SECRET_KEY.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='superset',
  image=defaultImage,
  replicas=1,
  dbHost='superset-db-rw',
  dbPort=5432,
  dbName='superset',
  dbUser='superset',
  redisHost='superset-cache',
  redisPort=6379,
  // A Secret carrying SUPERSET_SECRET_KEY and DB_PASS.
  secretName='superset',
  // Gunicorn workers inside the pod; each one holds a full Superset process.
  webWorkers=4,
  // Appended to the rendered superset_config.py, verbatim, for the settings this
  // stage does not model.
  extraConfig='',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '3Gi' } },
  labels={},
  annotations={},
)
  // The password is read from the environment INSIDE the configuration file
  // rather than interpolated into it, so the metadata database's credential never
  // lands in a ConfigMap.
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

  local settingsEnv = {
    SUPERSET_CONFIG_PATH: '/app/pythonpath/superset_config.py',
    PYTHONPATH: '/app/pythonpath:/app',
    SUPERSET_HOME: '/app/superset_home',
  } + env;

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8088)
  + kurly.servicePort(8088)
  + kurly.command(['gunicorn'])
  + kurly.args([
    '--bind=0.0.0.0:8088',
    '--workers=' + webWorkers,
    '--worker-class=gthread',
    '--threads=20',
    '--timeout=300',
    'superset.app:create_app()',
  ])
  + kurly.env(settingsEnv)
  // The uid the image's own superset user carries.
  + kurly.runAs(1000, gid=1000)
  + kurly.scratch('/tmp', '2Gi')
  + kurly.scratch('/app/superset_home', '1Gi')
  + kurly.envFromSecret(secretName)
  + kurly.config({ 'superset_config.py': settings + extraConfig }, mountPath='/app/pythonpath')
  + kurly.initContainer({
    name: 'db-upgrade',
    image: image,
    command: ['sh', '-c', 'superset db upgrade && superset init'],
    env: [{ name: k, value: settingsEnv[k] } for k in std.objectFields(settingsEnv)],
    envFrom: [{ secretRef: { name: secretName } }],
    volumeMounts: [
      { name: 'config', mountPath: '/app/pythonpath', readOnly: true },
      { name: 'app-superset-home', mountPath: '/app/superset_home' },
      { name: 'tmp', mountPath: '/tmp' },
    ],
    resources: { requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  })
  + kurly.startupProbe({ httpGet: { path: '/health', port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
