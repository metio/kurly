// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// redash — a Redash web server (query your data sources, save the queries, and
// build dashboards other people read). A composable kurly.http workload on the
// official image: gunicorn on :5000, with an EXTERNAL PostgreSQL holding the
// queries, dashboards and users and an EXTERNAL Redis carrying the job queues —
// the cnpg-cluster and valkey workloads provide them. It claims no volume; query
// results live in the database. Import it and render with kurly.list:
//
//   local redash = import 'github.com/metio/kurly/workloads/redash/server.libsonnet';
//   kurly.list(redash(host='https://redash.example.com'))
//
// Serves the UI and API on :5000 — compose an exposure onto it.
//
// IT IS ONLY A THIRD OF A DEPLOYMENT: the web server enqueues every query rather
// than running it, so without the `worker` stage a query submitted from the UI
// waits forever, and without the `scheduler` stage no query ever refreshes on its
// own. Run all three against the same database, the same Redis and the same
// Secret.
//
// THE SCHEMA IS NOT MIGRATED ON START. The image carries the migration as its own
// entrypoint command (`create_db` on an empty database, `manage db upgrade`
// afterwards), so a fresh deployment runs it once before these stages are useful:
//
//   kubectl run redash-create-db --rm -it --restart=Never \
//     --image=<the pinned image> --env=REDASH_DATABASE_URL=… -- create_db
//
// SECRETS: REDASH_DATABASE_URL, REDASH_REDIS_URL, REDASH_SECRET_KEY and
// REDASH_COOKIE_SECRET are read from the environment via envFrom. The cookie
// secret signs the session cookie — a value that changes on every restart signs
// everybody out — and the secret key encrypts the data source credentials stored
// in the database, so changing it later makes every configured data source
// unreadable. kurly authors no Secret.
//
// HOST is the public URL Redash builds its links and its mails from. It defaults
// to a value that boots rather than one that is right.
//
// Probed by CONNECTION: the root path redirects an unauthenticated visitor to the
// login form, and a probe that follows a redirect fails the day the redirect
// changes.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='redash',
  image=defaultImage,
  // The public URL the browser reaches this instance at, links and mails are
  // built from it.
  host='http://localhost:5000',
  // The Secret holding REDASH_DATABASE_URL, REDASH_REDIS_URL, REDASH_SECRET_KEY
  // and REDASH_COOKIE_SECRET (kurly mints none), pulled in via envFrom.
  secretName='redash',
  // Gunicorn worker processes inside the pod. Memory scales with it.
  webWorkers='4',
  // Whether anybody may create an account, or only an admin may invite one.
  passwordLoginEnabled=true,
  inviteOnly=true,
  replicas=1,
  // Extra environment (REDASH_MAIL_*, REDASH_GOOGLE_CLIENT_ID, …), merged over
  // the below. Anything sensitive belongs in the Secret, not a literal here.
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(5000)
  + kurly.servicePort(5000)
  + kurly.args(['server'])
  + kurly.envFromSecret(secretName)
  + kurly.env(
    {
      PYTHONUNBUFFERED: '0',
      REDASH_LOG_LEVEL: 'INFO',
      REDASH_HOST: host,
      REDASH_WEB_WORKERS: webWorkers,
      REDASH_PASSWORD_LOGIN_ENABLED: (if passwordLoginEnabled then 'true' else 'false'),
      REDASH_INVITE_ONLY: (if inviteOnly then 'true' else 'false'),
    } + env
  )
  // Every setting Redash reads is REDASH_-prefixed, and a Service named after the
  // workload makes Kubernetes inject REDASH_PORT as a tcp:// URL into exactly that
  // namespace. Turn the links off rather than hope no setting collides.
  + kurly.disableServiceLinks()
  // The image creates and selects the `redash` account; pin its uid so kubelet can
  // check runAsNonRoot, which it cannot do for a user given by name.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // gunicorn and the query runners write scratch files while the root filesystem
  // stays read-only.
  + kurly.scratch('/tmp', '256Mi')
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
