// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// snypy — a SnyPy backend (stores and shares code snippets across a team). A plain
// composable kurly.http workload on the official image, backed by an EXTERNAL
// PostgreSQL — the cnpg-cluster workload provides one. Import it, point it at a
// database, and render with kurly.list:
//
//   local snypy = import 'github.com/metio/kurly/workloads/snypy/server.libsonnet';
//   kurly.list(snypy())
//
// Serves the REST API and the Django admin on :8000 — compose an exposure onto it.
// Everything it stores is in PostgreSQL, so it claims no volume and can run several
// replicas.
//
// This is the API HALF of SnyPy. The web interface is a separate image
// (ghcr.io/snypy/snypy-ui) that talks to this one from the BROWSER, so the URLs
// below are the ones a user's browser resolves, not in-cluster addresses.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='snypy',
  image=defaultImage,
  // The public URL of the SnyPy web interface. The verification and password-reset
  // mails carry links built from it, so a wrong value sends users to a page that is
  // not there. Upstream's own published default is kept rather than invented, and it
  // is wrong for every real deployment — set it.
  frontendUrl='http://localhost:4200',
  // The Host headers Django accepts, and the browser origins allowed to call the API.
  // The default accepts any Host because a Deployment is reached by pod IP, Service
  // name and whatever the exposure calls it, and a Host Django rejects answers 400 —
  // narrow it once the exposure's hostname is known.
  allowedHosts=['*'],
  corsOrigins=[frontendUrl],
  csrfTrustedOrigins=[frontendUrl],
  // The Secret holding DATABASE_URL and SECRET_KEY (kurly mints none), pulled into
  // the environment via envFrom. The database password is embedded in DATABASE_URL;
  // the defaults pair with a cnpg-cluster named snypy-db. SECRET_KEY signs sessions
  // and the registration and password-reset tokens — upstream's example value is
  // literally `changeme!`.
  secretName='snypy',
  replicas=1,
  // gunicorn worker processes. Each one is a full copy of Django, so raising this
  // raises the memory limit the pod needs with it.
  workers=2,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(
    {
      DEBUG: 'False',
      RUN_MODE: 'production',
      GUNICORN_WORKERS: std.toString(workers),
      BIND_ADDRESS: '0.0.0.0:8000',
      ALLOWED_HOSTS: std.join(',', allowedHosts),
      CORS_ORIGIN_WHITELIST: std.join(',', corsOrigins),
      CSRF_TRUSTED_ORIGINS: std.join(',', csrfTrustedOrigins),
      REGISTER_VERIFICATION_URL: frontendUrl + '/verify-user/',
      REGISTER_EMAIL_VERIFICATION_URL: frontendUrl + '/verify-email/',
      RESET_PASSWORD_VERIFICATION_URL: frontendUrl + '/reset-password/?token={token}',
      SENTRY_ENABLED: 'False',
      // collectstatic runs on every start and writes the whole admin and API-browser
      // asset tree; the image's default target is /static, which the read-only root
      // does not allow.
      STATIC_ROOT: '/static',
    } + env
  )
  + kurly.envFromSecret(secretName)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The collected assets, rewritten on every start — they are derived from the image
  // and nothing reads them after the pod is gone, so a scratch is the whole story.
  + kurly.scratch('/static', '256Mi')
  + kurly.scratch('/tmp', '64Mi')
  // Django migrates the database and collects static files before gunicorn binds.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 45 })
  // Connection probes, not HTTP: the API is authenticated everywhere and there is no
  // route at /, so every path a probe could name answers 401, 404 or a redirect —
  // each of which would kill the pod for good.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
