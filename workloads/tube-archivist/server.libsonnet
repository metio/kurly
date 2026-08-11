// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tube-archivist — a Tube Archivist server (subscribe to YouTube channels and
// playlists, download what they publish and serve the result as your own media
// library, searchable and with playback progress kept). A composable kurly.http
// workload with two PersistentVolumes — a small one for the cache and artwork, a
// large one for the media — and two EXTERNAL dependencies it cannot supply
// itself. Import it and render with kurly.list:
//
//   local tubearchivist = import 'github.com/metio/kurly/workloads/tube-archivist/server.libsonnet';
//   kurly.list(tubearchivist(taHost='https://tube.example.com'))
//
// Serves nginx and the Django backend behind it on :8000 — compose an exposure
// onto it.
//
// Everything indexed lives in Elasticsearch 8, and the task queue in Redis;
// neither is optional and neither is rendered here (an opensearch-cluster does
// NOT substitute — Tube Archivist pins the Elasticsearch client). The cache
// volume holds artwork and yt-dlp state, the media volume the videos.
//
// taHost is the one value nobody else can supply: Django validates the request
// origin against it and answers everything else with a 400, so a placeholder
// would be wrong everywhere this is really deployed. Unset it is simply omitted
// rather than guessed, and the application refuses to start until it is given —
// deliberately, because a wrong origin looks exactly like a broken deployment.
//
// Single writer: one media tree and one cache on ReadWriteOnce volumes, so one
// replica, recreated (never rolled) — and also because two schedulers would
// download the same videos twice.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='tube-archivist',
  image=defaultImage,
  // The public origin the instance is reached at, protocol included. Django
  // rejects any request whose origin does not match.
  taHost=null,
  // Downloaded media, which is the half that grows without limit.
  mediaSize='500Gi',
  // Artwork, yt-dlp state and the download cache.
  storageSize='10Gi',
  storageClass=null,
  esUrl='http://tube-archivist-es:9200',
  redisCon='redis://tube-archivist-cache-headless:6379',
  timezone='UTC',
  // The Secret holding TA_USERNAME and TA_PASSWORD (the first administrator, read
  // once when the account is created) and ELASTIC_PASSWORD (the Elasticsearch
  // credential). kurly mints none of them.
  secretName='tube-archivist',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env({
    [if taHost != null then 'TA_HOST']: taHost,
    ES_URL: esUrl,
    REDIS_CON: redisCon,
    TZ: timezone,
  } + env)
  + kurly.envFromSecret(secretName)
  // The image selects no account: nginx is configured to run as root and the
  // startup script runs the migrations, collectstatic and the celery workers as
  // whoever started them, with no path that drops privileges. Nothing here
  // escalates, so the capability set stays dropped.
  + kurly.rootUser()
  // nginx wants /var/lib/nginx, /var/log/nginx and /run, collectstatic writes the
  // built assets into /app/static beside the code, and the optional yt-dlp
  // self-update installs into /root/.local. None of that is data worth a volume,
  // and all of it is outside the two mounts.
  + kurly.writableRootFilesystem()
  // NGINX'S LOG DIRECTORY, and a writable root filesystem is not enough for it.
  // The image ships /var/log/nginx/{access,error}.log owned by www-data with mode
  // 0640, while this runs as root with every capability dropped — and root without
  // DAC_OVERRIDE may not write another user's file, though it may still create new
  // ones in the directory, which is why the directory itself looks fine. nginx
  // exits on "open() /var/log/nginx/error.log failed (13: Permission denied)"
  // while the same run.sh goes on to start celery, so the pod reports a healthy
  // worker and nothing ever listens on the HTTP port. An empty volume gives nginx
  // its own directory rather than handing the capability back.
  + kurly.scratch('/var/log/nginx', '64Mi')
  // Artwork, thumbnails and yt-dlp's own state.
  + kurly.store('/cache', storageSize, storageClass=storageClass)
  // The downloaded videos.
  + kurly.store('/youtube', mediaSize, storageClass=storageClass)
  // The first start waits for Elasticsearch to answer, builds every index,
  // migrates the Django schema and collects the static assets before nginx has
  // anything to serve.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  // Probed by connection: every path redirects to a login and answers 403 to an
  // unauthenticated request, so an HTTP probe would restart a healthy pod forever.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
