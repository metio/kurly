// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// upvote-rss — an Upvote RSS server (turns a subreddit, a Hacker News front page
// or a Lemmy community into a full-text RSS feed, filtered by score). A plain
// composable kurly.http workload keeping its response cache on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local upvoteRss = import 'github.com/metio/kurly/workloads/upvote-rss/server.libsonnet';
//   kurly.list(upvoteRss())
//
// Serves the feed builder and the feeds themselves on :80 — compose an exposure
// onto it.
//
// It fetches every article it summarises from the site that published it, so the
// pod needs egress to the internet; a NetworkPolicy that forgets this leaves the
// feeds empty.
//
// There is no authentication. Anyone who reaches it can build feeds through it,
// which makes it a fetcher for arbitrary URLs on whatever network the pod sits
// on — keep it in-cluster or put an authenticating proxy in front.
//
// Single writer: one filesystem cache on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='upvote-rss',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  // The Secret holding the credentials the feeds are built with — Reddit's
  // client id and secret, and an API key for whichever summarisation service is
  // configured. Every one of them is optional: without them Reddit is read
  // anonymously and articles are not summarised.
  secretName=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // frankenphp serves /app on :80 in the image's own command.
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  // PHP publishes the process environment as $_SERVER, and the application reads
  // REDIS_HOST and REDIS_PORT from there. A Service named `redis` in the same
  // namespace would inject REDIS_PORT as a tcp:// URL and the cache backend
  // would be configured by an unrelated workload's name.
  + kurly.disableServiceLinks()
  // The entrypoint chowns /app and /data and then drops to the upvote-rss
  // account with su-exec, which it can only do from root.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // The image ships no upvote-rss account: the entrypoint creates the group and
  // the user at every start, which writes /etc/passwd and /etc/group. On a
  // read-only root filesystem those writes fail without stopping the script, and
  // the container dies on `su-exec: getpwnam(upvote-rss)` instead.
  + kurly.writableRootFilesystem()
  + kurly.store('/app/cache', storageSize, storageClass=storageClass)
  // The application writes its log beside its own code, and frankenphp keeps
  // Caddy's data and configuration under the image's XDG directories.
  + kurly.scratch('/app/logs')
  + kurly.scratch('/data')
  + kurly.scratch('/config')
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
