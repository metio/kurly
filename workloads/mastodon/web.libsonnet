// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mastodon (web) — the Mastodon web/API server: the Rails app of Mastodon, the leading
// self-hosted ActivityPub/Fediverse microblogging platform. Mastodon runs as THREE workloads —
// this web server, a `streaming` server for real-time timelines, and a `sidekiq` background
// worker — backed by an external PostgreSQL and Redis, with media in S3-compatible object
// storage. Import it, point it at its backends, and render with kurly.list:
//
//   local web = import 'github.com/metio/kurly/workloads/mastodon/web.libsonnet';
//   kurly.list(web(localDomain='social.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// LOCAL DOMAIN IS PERMANENT: LOCAL_DOMAIN is baked into every account's @handle and cannot be
// changed later, so set it deliberately.
//
// BACKENDS & SECRETS: Mastodon reads its PostgreSQL and Redis connection, the SECRET_KEY_BASE,
// OTP_SECRET, the VAPID keys, and the S3 settings from the environment. kurly authors no Secret;
// provide one holding them, via envFrom. All three stages share it. Pairs with a cnpg-cluster
// named mastodon-db, a Redis and an S3 bucket (e.g. seaweedfs).
//
// Stateless (with S3 media): a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='mastodon',
  image='ghcr.io/mastodon/mastodon:v4.3.1',
  replicas=2,
  localDomain=null,
  secretName='mastodon-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '768Mi' }, limits: { memory: '1536Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if localDomain == null then {} else { LOCAL_DOMAIN: localDomain };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.command(['bundle', 'exec', 'puma', '-C', 'config/puma.rb'])
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env({ RAILS_ENV: 'production' } + baseEnv + env)
  + kurly.runAs(991, gid=991, fsGroup=991)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/mastodon/tmp', '256Mi')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
