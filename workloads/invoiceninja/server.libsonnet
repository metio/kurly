// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// invoiceninja — an Invoice Ninja server (self-hosted invoicing, quotes, and
// payments). A plain composable kurly.http workload on the official image, backed
// by an external MySQL/MariaDB, with its uploads and generated PDFs on a
// PersistentVolume. Import it, point it at a database, and render with kurly.list:
//
//   local invoiceninja = import 'github.com/metio/kurly/workloads/invoiceninja/server.libsonnet';
//   kurly.list(invoiceninja(appUrl='https://invoicing.example.com'))
//
// Serves the web app and API on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: Invoice Ninja needs a MySQL/MariaDB database (kurly ships no
// MySQL recipe — bring your own, or an operator-managed one). It reads DB_HOST,
// DB_DATABASE, DB_USERNAME from env and DB_PASSWORD and APP_KEY from a provided
// Secret via envFrom. kurly authors no Secret.
//
// The nginx + PHP-FPM image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: uploads and PDFs live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='invoiceninja',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  dbHost='invoiceninja-db',
  dbName='invoiceninja',
  dbUser='invoiceninja',
  // The public URL Invoice Ninja builds links against.
  appUrl=null,
  // The Secret holding DB_PASSWORD and APP_KEY (kurly mints none), via envFrom.
  secretName='invoiceninja',
  // The web server in front of php-fpm. The application image ships FastCGI only,
  // so nginx serves the document root beside it in the same pod.
  nginxImage='docker.io/library/nginx:1.29.4-alpine',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  // nginx in front of php-fpm: static files served directly, everything else
  // forwarded to the application container over the pod's loopback.
  local nginxConf = |||
    server {
      listen 80;
      root /var/www/app/public;
      index index.php;
      client_max_body_size 64M;
      location / {
        try_files $uri $uri/ /index.php?$query_string;
      }
      location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
      }
    }
  |||;
  local baseEnv = {
    DB_CONNECTION: 'mysql',
    DB_HOST: dbHost,
    DB_PORT: '3306',
    DB_DATABASE: dbName,
    DB_USERNAME: dbUser,
  } + (if appUrl == null then {} else { APP_URL: appUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  // php-fpm drops its worker pool from root, and the nginx sidecar hands its cache
  // directories to the nginx user before dropping to it.
  + kurly.keepCapabilities()
  // Kept: the entrypoint DELETES files from its own image tree — rm on every
  // .gitignore under /var/www/app/docker-backup-storage — and nginx creates its
  // cache under /var/cache/nginx. Removing image content is not something a
  // scratch can provide: an emptyDir would hide the tree it is pruning.
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/app/storage', storageSize, storageClass=storageClass)
  // The document root is shared with the nginx sidecar: nginx serves the static
  // files itself and hands every PHP request to php-fpm on localhost, so both
  // containers must see the same tree. An init container seeds it from the image.
  + kurly.scratch('/var/www/app/public', '512Mi')
  + kurly.initContainer({
    name: 'public',
    image: image,
    command: ['sh', '-c', 'cp -a /var/www/app/public/. /shared-public/'],
    volumeMounts: [{ name: 'var-www-app-public', mountPath: '/shared-public' }],
  })
  + kurly.config({ 'default.conf': nginxConf }, '/etc/nginx/conf.d')
  + kurly.sidecar({
    name: 'nginx',
    image: nginxImage,
    ports: [{ containerPort: 80, name: 'http', protocol: 'TCP' }],
    volumeMounts: [
      { name: 'var-www-app-public', mountPath: '/var/www/app/public' },
      { name: 'config', mountPath: '/etc/nginx/conf.d', readOnly: true },
    ],
    readinessProbe: { tcpSocket: { port: 80 } },
    resources: { requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
