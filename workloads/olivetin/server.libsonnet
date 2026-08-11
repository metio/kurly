// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// olivetin — a web interface that turns a handful of shell commands into
// buttons, for the people who should be allowed to run them and nothing else. A
// plain composable kurly.http workload: its whole state is config.yaml, rendered
// as a ConfigMap, so it needs no database and no PersistentVolume. Import it and
// render with kurly.list:
//
//   local olivetin = import 'github.com/metio/kurly/workloads/olivetin/server.libsonnet';
//   kurly.list(olivetin(actions=[{ title: 'Check disk space', shell: 'df -h /' }]))
//
// Serves the web UI and REST API on :1337 — compose an exposure onto it.
//
// WHAT THE BUTTONS CAN REACH: every action is a shell command run INSIDE THIS
// CONTAINER, so it can only use what the image ships and can only touch what this
// pod can touch. That is the security boundary worth thinking about before
// exposing it: anything the container can do, a button can do. The image ships no
// actions of its own here — `actions` starts empty rather than carrying the
// upstream demo set, which invites `cat ~/.bash_history` through a web page.
//
// Stateless: nothing is written outside /tmp, which is a scratch volume, so the
// root filesystem stays read-only and any replica count is safe.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='olivetin',
  image=defaultImage,
  replicas=1,
  // OliveTin action definitions, verbatim — see https://docs.olivetin.app.
  actions=[],
  logLevel='INFO',
  // Merged over the rendered config.yaml — any of OliveTin's other settings.
  config={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(1337)
  + kurly.servicePort(1337)
  // The uid and gid the image's own olivetin user carries.
  + kurly.runAs(1000, gid=999)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.config({
    'config.yaml': std.manifestYamlDoc({
      listenAddressSingleHTTPFrontend: '0.0.0.0:1337',
      logLevel: logLevel,
      actions: actions,
    } + config, quote_keys=false),
  }, mountPath='/config')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
