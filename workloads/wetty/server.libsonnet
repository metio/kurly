// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wetty — a WeTTY server (a terminal in the browser: it opens an SSH connection to
// a host you name and renders it as a web page). A plain composable kurly.http
// workload and a stateless one — it stores nothing, so it claims no volume.
// Import it and render with kurly.list:
//
//   local wetty = import 'github.com/metio/kurly/workloads/wetty/server.libsonnet';
//   kurly.list(wetty(sshHost='bastion.internal'))
//
// Serves the terminal on :3000 — compose an exposure onto it.
//
// THINK ABOUT WHAT THIS IS BEFORE EXPOSING IT. WeTTY turns an HTTP request into a
// shell session on `sshHost`. It performs no authentication of its own: anyone who
// reaches the page gets the SSH login prompt, and anyone who has credentials for
// that host gets a shell. Put an authenticating proxy in front of it, keep it on
// an internal route, or point it at a host that is meant to be reachable that way
// — kurly cannot make that judgement, and the default here authenticates nobody.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='wetty',
  image=defaultImage,
  // The host WeTTY opens an SSH connection to. REQUIRED: with nothing set it
  // defaults to localhost, which inside a container is the WeTTY pod itself — a
  // terminal that connects to a machine with no sshd and fails on every attempt.
  sshHost=null,
  sshPort=22,
  // The account WeTTY offers. Left unset, the user types their own name at the
  // prompt, which is usually what a shared bastion terminal should do.
  sshUser=null,
  // Where the terminal is served under, for hosting it beside other things on one
  // hostname.
  base='/wetty/',
  replicas=1,
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
    { BASE: base, SSHPORT: std.toString(sshPort) }
    + (if sshHost == null then {} else { SSHHOST: sshHost })
    + (if sshUser == null then {} else { SSHUSER: sshUser })
    + env
  )
  // Node needs nothing root provides here: the port is above 1024 and nothing is
  // written outside /tmp.
  + kurly.runAs(1000, gid=1000)
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: base, port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: base, port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
