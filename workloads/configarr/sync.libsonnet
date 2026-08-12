// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// configarr — keeps the quality profiles, custom formats and naming settings of
// a Sonarr/Radarr-style application in step with TRaSH Guides and with a
// configuration you keep in Git. A composable kurly.cron workload, because that
// is what it is: it runs, reconciles, and exits. Import it and render with
// kurly.list:
//
//   local configarr = import 'github.com/metio/kurly/workloads/configarr/sync.libsonnet';
//   kurly.list(configarr(
//     services={ sonarr: { base_url: 'http://sonarr:8989', api_key: '!secret SONARR_API_KEY' } },
//     secretName='configarr',
//   ))
//
// IT WRITES TO THE APPLICATIONS IT POINTS AT. Every run replaces the profiles and
// formats it manages in Sonarr or Radarr with what the configuration says. That is
// the whole point, and it means a hand-made change in the web UI is undone at the
// next run rather than merged — the configuration here is the source of truth or
// configarr should not be pointed at that instance.
//
// API KEYS DO NOT BELONG IN THE CONFIGMAP. configarr resolves `!secret NAME` in
// its config.yml from a secrets.yml file, which is mounted here from the Secret
// `secretName` names. Writing a key inline would put it in a ConfigMap, readable
// by anything that can read ConfigMaps in the namespace.
//
// The TRaSH Guides repository is cloned on each run, so the pod needs egress to
// GitHub; `localConfigTemplatesPath` is the alternative for a cluster that has
// none.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './sync.image', '\n');

function(
  name='configarr',
  image=defaultImage,
  // Daily at 04:00 — often enough to pick up guide changes, rare enough that a
  // run is never a surprise.
  schedule='0 4 * * *',
  // One entry per managed application, keyed by kind (sonarr, radarr, …), each a
  // configarr service definition passed through verbatim.
  services={},
  // Merged over the rendered config.yml — trashGuideUrl, custom formats,
  // quality definitions and the rest.
  config={},
  // A Secret holding secrets.yml, the file configarr resolves `!secret NAME`
  // against.
  secretName=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.cron(name, image, schedule)
  + kurly.version(version)
  + kurly.env(env)
  // The image runs as root by default; configarr reads its configuration, clones
  // a repository into a scratch volume and talks HTTP, so an unprivileged uid
  // serves.
  + kurly.runAs(1000, gid=1000)
  + kurly.config({
    'config.yml': std.manifestYamlDoc({ trashGuideUrl: 'https://github.com/TRaSH-Guides/Guides' } + config + services, quote_keys=false),
  }, mountPath='/app/config', subPath=true)
  + (if secretName != null then kurly.secretMount(secretName, '/app/config/secrets.yml', subPath='secrets.yml') else {})
  // The guides repository is cloned here on every run.
  + kurly.scratch('/app/repos', '512Mi')
  + kurly.scratch('/tmp', '128Mi')
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
