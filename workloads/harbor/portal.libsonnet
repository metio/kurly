// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// harbor/portal — the Harbor web UI: an nginx serving the compiled Angular
// application. It holds no state and talks to nothing; the browser it serves
// calls the core API directly, so an exposure has to route `/` here and
// `/api/`, `/service/`, `/v2/` and `/c/` to the core stage.
//
//   local portal = import 'github.com/metio/kurly/workloads/harbor/portal.libsonnet';
//   kurly.list([portal(), …])
//
// Serves on :8080.
//
// The nginx configuration is rendered into a ConfigMap rather than taken from
// the image, because the image's own copy writes its temporary files under
// /var/cache/nginx: it puts every temp path and the pid file under /tmp, which
// is what lets the pod keep a read-only root filesystem.
//
// Stateless: a plain rolling Deployment that scales horizontally.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './portal.image', '\n');

function(
  name='harbor-portal',
  image=defaultImage,
  replicas=1,
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
  podLabels={},
  podAnnotations={},
)
  local nginxConf = |||
    worker_processes auto;
    pid /tmp/nginx.pid;
    events {
        worker_connections 1024;
    }
    http {
        client_body_temp_path /tmp/client_body_temp;
        proxy_temp_path /tmp/proxy_temp;
        fastcgi_temp_path /tmp/fastcgi_temp;
        uwsgi_temp_path /tmp/uwsgi_temp;
        scgi_temp_path /tmp/scgi_temp;
        server {
            listen 8080;
            listen [::]:8080;
            server_name localhost;
            root /usr/share/nginx/html;
            index index.html index.htm;
            include /etc/nginx/mime.types;
            gzip on;
            gzip_min_length 1000;
            gzip_proxied expired no-cache no-store private auth;
            gzip_types text/plain text/css application/json application/javascript application/x-javascript text/xml application/xml application/xml+rss text/javascript;
            location /devcenter-api-2.0 {
                try_files $uri $uri/ /swagger-ui-index.html;
            }
            location / {
                try_files $uri $uri/ /index.html;
            }
            location = /index.html {
                add_header Cache-Control "no-store, no-cache, must-revalidate";
            }
        }
    }
  |||;

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.runAs(10000, gid=10000, fsGroup=10000)
  // A single-file mount: /etc/nginx also holds the mime.types the server block
  // includes, so the directory must survive.
  + kurly.config({ 'nginx.conf': nginxConf }, mountPath='/etc/nginx', subPath=true)
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' }, periodSeconds: 10 })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' }, initialDelaySeconds: 20, periodSeconds: 20 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + kurly.podLabels(podLabels)
  + kurly.podAnnotations(podAnnotations)
