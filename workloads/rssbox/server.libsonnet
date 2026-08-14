// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// rssbox — turns sites that stopped publishing feeds back into RSS: YouTube
// channels, Twitch streams, SoundCloud, Vimeo, Instagram and a dozen more, each
// as a feed a reader can subscribe to. A plain composable kurly.http workload
// holding no state. Import it and render with kurly.list:
//
//   local rssbox = import 'github.com/metio/kurly/workloads/rssbox/server.libsonnet';
//   kurly.list(rssbox(secretName='rssbox'))
//
// Serves the site and every feed on :3000 — compose an exposure onto it.
//
// MOST SERVICES NEED AN API KEY THAT IS YOURS, NOT THE APPLICATION'S. YouTube,
// Vimeo, SoundCloud, Twitch and Imgur each want a credential registered in your
// name, supplied through `secretName`; Instagram, Mixcloud, Speedrun and
// Dailymotion work without one. A missing key does not stop the server — that
// service's feeds simply fail — so an instance can be deployed with none and
// grown as the credentials are obtained.
//
// REDIS IS OPTIONAL AND ONLY FOR ONE FEATURE. It caches URL resolution; without
// it everything else works. `redisUrl` wires one in when there is one.
//
// IT FETCHES THE PUBLIC INTERNET ON EVERY REQUEST, which is the whole function:
// a cluster with default-deny egress gives it nothing to convert, and each feed
// a reader polls is a request to somebody else's API against your quota.
//
// Stateless: nothing is written, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='rssbox',
  image=defaultImage,
  replicas=1,
  // A Redis for the URL-resolution cache. Everything else works without one.
  redisUrl=null,
  // A Secret carrying the per-service API keys — GOOGLE_API_KEY,
  // TWITCH_CLIENT_ID, SOUNDCLOUD_CLIENT_ID and the rest.
  secretName=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(
    // HOME, because the image's own user has /nonexistent as its home and both
    // bundler and puma try to write there before anything serves.
    { RACK_ENV: 'production', PORT: '3000', HOME: '/tmp' }
    + (if redisUrl != null then { REDIS_URL: redisUrl } else {})
    + env
  )
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  // The uid the image's own nobody user carries.
  + kurly.runAs(65534, gid=65534)
  // Puma writes its pid and socket state under /tmp, and bundler insists on a
  // writable cache INSIDE the application tree — /app/tmp/cache, which it creates
  // before loading the app and refuses to start without.
  + kurly.scratch('/tmp', '64Mi')
  + kurly.scratch('/app/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
