// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// librephotos-proxy — the nginx edge that makes LibrePhotos one origin: it serves
// the frontend at /, forwards /api and /media to the backend, and hands out the
// photos and thumbnails the backend delegates to it with X-Accel-Redirect. This
// is the stage you expose. One of the three LibrePhotos stages — see the backend
// stage's header and the workload README for the whole picture.
//
//   local proxy = import 'github.com/metio/kurly/workloads/librephotos/proxy.libsonnet';
//   kurly.list(proxy() + kurly.expose.ingress('photos.example.com'))
//
// Serves on :8080.
//
// CONFIGURATION: the image ships an nginx.conf whose upstreams are the literal
// names `backend` and `frontend`, which no namespace running two copies can
// satisfy. This stage renders its own equivalent from the stage names instead, so
// the whole workload follows `namePrefix` — including the internal locations, which
// are aliased at the backend's volume rather than at the image's hardcoded paths.
//
// STORAGE: nginx serves the originals and the generated media straight off the
// backend's volume, so it mounts that claim read-only. With the backend's
// ReadWriteOnce default both pods must schedule onto the same node; give the
// backend a ReadWriteMany class to spread them, or set serveMedia=false to run
// without the mount — downloads and full-size images then 404.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './proxy.image', '\n');

function(
  namePrefix='librephotos',
  name=null,
  image=defaultImage,
  replicas=1,
  backendHost=null,
  backendPort=8001,
  frontendHost=null,
  frontendPort=3000,
  // The backend's claim, mounted read-only at dataRoot; null derives the name the
  // backend stage's store renders.
  storageClaim=null,
  // Serve the originals and the generated media off that claim. Turning it off
  // drops the mount — and with it the downloads and full-size images, which the
  // backend only ever delegates.
  serveMedia=true,
  // Where the backend's BASE_DATA lives, and therefore where its `data` and
  // `protected_media` directories are found.
  dataRoot='/librephotos',
  // The upload ceiling nginx enforces before the backend ever sees the request.
  maxBodySize='500m',
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-proxy';
  local backend = (if backendHost != null then backendHost else namePrefix + '-backend') + ':' + backendPort;
  local frontend = (if frontendHost != null then frontendHost else namePrefix + '-frontend') + ':' + frontendPort;
  local claim = if storageClaim != null then storageClaim else namePrefix + '-backend-store';

  // The image's own nginx.conf, restated over the stage's names and paths. It
  // keeps the upstream's Content-Security-Policy (MapLibre GL needs the inline
  // and blob sources, plus the tile and glyph hosts of the map providers the
  // Site Settings offer) and its internal locations, which are the second half of
  // the backend's X-Accel-Redirect: Django authorises the request and answers with
  // a path only nginx may serve.
  local nginxConf = |||
    worker_processes  1;
    pid /tmp/nginx.pid;
    error_log  /dev/stderr warn;

    events {
        worker_connections  1024;
    }

    http {
      include       /etc/nginx/mime.types;
      access_log    /dev/stdout;
      client_body_temp_path /tmp/client_body;
      proxy_temp_path       /tmp/proxy;
      fastcgi_temp_path     /tmp/fastcgi;
      uwsgi_temp_path       /tmp/uwsgi;
      scgi_temp_path        /tmp/scgi;
      client_max_body_size  %(maxBodySize)s;

      server {
        listen 8080;

        add_header X-Frame-Options "DENY";
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; style-src 'self' 'unsafe-inline' https://cdn.photoprism.app; img-src 'self' data: blob: https://maps.photoprism.app https://cdn.photoprism.app https://tile.openstreetmap.org; font-src 'self' https://cdn.photoprism.app; connect-src 'self' https://maps.photoprism.app https://cdn.photoprism.app https://tile.openstreetmap.org https://fonts.openmaptiles.org; worker-src 'self' blob:; child-src 'self' blob:;";

        location / {
          # The React routes live in the browser, so an unknown path is the app,
          # not a 404.
          error_page 404 /;
          proxy_intercept_errors on;
          proxy_set_header Host $host;
          proxy_pass http://%(frontend)s/;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        }

        # Zip downloads are served from disk, so this has to precede /api.
        location ~ ^/api/downloads/(.*)$ {
          root /;
          try_files %(mediaRoot)s/zip/$1.zip =404;
        }

        location ~ ^/(api|media)/ {
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Real-IP $remote_addr;
          # Django's ALLOWED_HOSTS is exactly ['localhost', BACKEND_HOST].
          proxy_set_header Host %(backendName)s;
          proxy_pass http://%(backend)s;
        }

        location /static/drf-yasg {
          proxy_pass http://%(backend)s;
        }

        location /protected_media {
          internal;
          alias %(mediaRoot)s/;
        }

        location /data {
          internal;
          alias %(photoRoot)s/;
        }

        location /original {
          internal;
          alias %(photoRoot)s/;
        }

        location /nextcloud_original {
          internal;
          alias %(photoRoot)s/nextcloud_media/;
        }
      }
    }
  ||| % {
    backend: backend,
    backendName: if backendHost != null then backendHost else namePrefix + '-backend',
    frontend: frontend,
    maxBodySize: maxBodySize,
    mediaRoot: dataRoot + '/protected_media',
    photoRoot: dataRoot + '/data',
  };

  local storage = {
    deployment+: { spec+: { template+: { spec+: {
      volumes+: [{ name: 'storage', persistentVolumeClaim: { claimName: claim, readOnly: true } }],
      containers: [
        container { volumeMounts+: [{ name: 'storage', mountPath: dataRoot, readOnly: true }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // A single file dropped beside the image's own mime.types and conf.d, not over
  // the directory that holds them.
  + kurly.config({ 'nginx.conf': nginxConf }, mountPath='/etc/nginx', subPath=true)
  // The official nginx image starts as root to rewrite its configuration and then
  // drops to the nginx user (uid 101). There is nothing to rewrite here, so run as
  // that uid from the start; the fsGroup is the backend's, so the media files it
  // wrote are readable.
  + kurly.runAs(101, gid=101, fsGroup=1000)
  // nginx buffers request bodies and upstream responses to disk, and writes its
  // pid file; scratches keep the root filesystem read-only.
  + kurly.scratch('/tmp', '1Gi')
  + kurly.scratch('/var/cache/nginx', '256Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + (if serveMedia then storage else {})
