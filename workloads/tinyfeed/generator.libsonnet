// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tinyfeed — a tinyfeed generator (a CLI that reads a list of RSS, Atom and JSON
// feeds and writes ONE static HTML page aggregating them). A plain composable
// kurly.worker workload running the CLI in its daemon mode, so the page is
// rewritten on an interval, onto a PersistentVolume. Import it and render with
// kurly.list:
//
//   local tinyfeed = import 'github.com/metio/kurly/workloads/tinyfeed/generator.libsonnet';
//   kurly.list(tinyfeed(feeds=['https://lovergne.dev/rss.xml']))
//
// THERE IS NO SERVER HERE, and that is the whole shape of the workload: tinyfeed
// is a static site generator, it binds no port and answers no request, so this is
// a worker with no Service and nothing to compose an exposure onto. Serving the
// page is a second workload — an HTTP server (kurly's caddy is one) mounting the
// same claim read-only. That needs a class supporting ReadWriteMany, or both pods
// scheduled onto one node; accessModes is a parameter for exactly that reason.
//
// The feed list is the workload: `feeds` is rendered to the input file the CLI
// reads (one URL per line, # comments allowed), mounted as a ConfigMap, so
// changing the list is a re-render rather than an exec into a pod.
//
// The image is FROM scratch around one static Go binary with a non-root USER, no
// shell and no entrypoint dropping privileges: it writes the output file and
// nothing else, so it keeps the fully restricted posture.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './generator.image', '\n');

// A working default so a bare render produces a real page: the project's own
// release feed. A real deployment replaces it.
local defaultFeeds = ['https://feed.lovergne.dev/releases.atom'];

function(
  name='tinyfeed',
  image=defaultImage,
  // The feeds to aggregate, one URL per entry. Rendered to the CLI's input file.
  feeds=defaultFeeds,
  storageSize='1Gi',
  storageClass=null,
  // ReadWriteMany lets the HTTP server serving the page run on another node.
  accessModes=['ReadWriteOnce'],
  // Where the page is written, on the volume, and what the server therefore
  // serves as its index.
  outputPath='/output/index.html',
  // Minutes between regenerations. tinyfeed's own default is a day.
  interval=1440,
  // The page's title and the line under it.
  title='Feed',
  description=null,
  // An external stylesheet and script the generated page links, and a custom
  // HTML+Go template — a path INSIDE the container, so a template comes from a
  // ConfigMap composed on with kurly.config.
  stylesheet=null,
  script=null,
  template=null,
  // How many articles the page shows in total and per feed.
  limit=256,
  limitPerFeed=256,
  // Extra CLI flags, appended verbatim after the ones above.
  extraArgs=[],
  env={},
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local feedsFile = std.join('\n', feeds) + '\n';

  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.config({ 'feeds.txt': feedsFile }, mountPath='/etc/tinyfeed')
  + kurly.args(
    [
      '--daemon',
      '--interval',
      std.toString(interval),
      '--input',
      '/etc/tinyfeed/feeds.txt',
      '--output',
      outputPath,
      '--name',
      title,
      '--limit',
      std.toString(limit),
      '--limit-per-feed',
      std.toString(limitPerFeed),
    ]
    + (if description == null then [] else ['--description', description])
    + (if stylesheet == null then [] else ['--stylesheet', stylesheet])
    + (if script == null then [] else ['--script', script])
    + (if template == null then [] else ['--template', template])
    + extraArgs
  )
  + kurly.env(env)
  // The image's own USER is the first alpine account, uid 1000; pinning it here
  // is what makes the volume writable by the process that writes the page.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/output', storageSize, accessModes=accessModes, storageClass=storageClass)
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
