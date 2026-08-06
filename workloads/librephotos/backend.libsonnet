// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// librephotos-backend — the Django/gunicorn half of LibrePhotos: the REST API, the
// django-q worker that does the thumbnailing, face detection and captioning, and
// the machine-learning models those services load. It holds all of the state: the
// photo library, the generated thumbnails and downloaded models under
// protected_media, and Django's own secret.key.
//
// LibrePhotos is three coordinated stages — backend, frontend and proxy — that
// share one name prefix and one volume; run all three, and point the proxy at this
// stage's claim. See the workload README.
//
//   local backend = import 'github.com/metio/kurly/workloads/librephotos/backend.libsonnet';
//   kurly.list(backend())
//
// Serves the API on :8001. It is NOT the thing you expose: the browser talks to
// the proxy, which serves the frontend and forwards /api and /media here.
//
// DATABASE: LibrePhotos needs PostgreSQL. The defaults point at a CNPG cluster
// named `librephotos-db` (its `-rw` Service). The task queue is django-q on the
// ORM broker, so no Redis is needed.
//
// STORAGE: one volume at `/librephotos` carries everything the settings derive
// from BASE_DATA and BASE_LOGS — `data` (the photo library), `protected_media`
// (thumbnails, face crops, downloaded ML models — plan for several times the
// library size) and `logs` (which is also where Django's secret.key lives, so a
// lost volume logs every session out). The proxy serves the protected_media and
// data files directly via X-Accel-Redirect, so it mounts this same claim.
//
// Single writer on a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the library.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './backend.image', '\n');

function(
  namePrefix='librephotos',
  name=null,
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  // ReadWriteMany lets the proxy read the media files from another node. With the
  // ReadWriteOnce default both pods must land on the same node.
  accessModes=['ReadWriteOnce'],
  dbHost='librephotos-db-rw',
  dbName='librephotos',
  dbUser='librephotos',
  dbPort='5432',
  // The Secret holding DB_PASS, SECRET_KEY and ADMIN_PASSWORD. The consumer
  // provides it; kurly mints none.
  secretName='librephotos',
  // The initial administrator, created on first start from ADMIN_PASSWORD in the
  // Secret. Clear adminUsername once the account exists.
  adminUsername='admin',
  adminEmail='admin@example.com',
  // How many django-q workers do the heavy lifting. Left unset the pool sizes
  // itself from the NODE's core count and a CPU limit only starves it.
  workerConcurrency=2,
  // Extra environment (FEATURE_* switches, MAPBOX_API_KEY, SKIP_PATTERNS, …),
  // merged over the below. Anything sensitive belongs in the Secret.
  env={},
  // The ML services load torch and insightface into the same pod, so this is a
  // memory-hungry workload even when idle.
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '6Gi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-backend';
  local dataRoot = '/librephotos';
  local baseEnv = {
    // BASE_DATA and BASE_LOGS are what the production settings derive PHOTOS
    // (<BASE_DATA>/data), MEDIA_ROOT (<BASE_DATA>/protected_media) and the
    // secret.key path from — pointing both at one volume keeps all state together.
    BASE_DATA: dataRoot,
    BASE_LOGS: dataRoot + '/logs',
    DB_BACKEND: 'postgresql',
    DB_HOST: dbHost,
    DB_NAME: dbName,
    DB_USER: dbUser,
    DB_PORT: dbPort,
    // Django's ALLOWED_HOSTS is exactly ['localhost', BACKEND_HOST], so the proxy
    // must send this name as the Host header — which is what the generated
    // nginx.conf in the proxy stage does.
    BACKEND_HOST: resolvedName,
    WORKER_CONCURRENCY: std.toString(workerConcurrency),
  } + (if adminUsername == null then {} else {
         ADMIN_USERNAME: adminUsername,
         ADMIN_EMAIL: adminEmail,
       });

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8001)
  + kurly.servicePort(8001)
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  + kurly.store(dataRoot, storageSize, accessModes=accessModes, storageClass=storageClass)
  // The image declares no USER and would run as root; pin an ordinary uid that
  // owns the volume through fsGroup.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // collectstatic writes STATIC_ROOT beside the code at /code/static, and the ML
  // subprocesses use /tmp; scratches there keep the root filesystem read-only.
  + kurly.scratch('/code/static', '512Mi')
  + kurly.scratch('/tmp', '1Gi')
  // First start applies the whole Django migration set, downloads the ML models
  // and builds the similarity index before gunicorn binds, which takes many
  // minutes on a cold volume.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 15, failureThreshold: 80 })
  // Every API path requires a JWT and answers 401 unauthenticated, so probe by
  // connection rather than on a path that would fail forever.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' }, periodSeconds: 15 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 60, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
