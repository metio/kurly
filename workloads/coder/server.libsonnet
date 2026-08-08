// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// coder — a Coder server (it provisions remote development workspaces on your own
// infrastructure from Terraform templates, and hands developers a browser IDE, SSH
// and port forwarding into them). A plain composable kurly.http workload on the
// official image, backed by an EXTERNAL PostgreSQL — the cnpg-cluster workload
// provides one — and keeping no state of its own. Import it, point it at its
// database, and render with kurly.list:
//
//   local coder = import 'github.com/metio/kurly/workloads/coder/server.libsonnet';
//   kurly.list(coder(accessUrl='https://coder.example.com'))
//
// Serves the web app, the API and the agent endpoints on :8080 — compose an
// exposure onto it.
//
// ACCESS URL: workspace agents dial back in on CODER_ACCESS_URL, so it must be the
// address they can reach, not the in-cluster Service name. Left unset the server
// still starts and falls back to localhost, at which point every workspace it
// creates comes up and never connects.
//
// PROVISIONING IS NOT INCLUDED: a template that creates Kubernetes workspaces needs
// a ServiceAccount with RBAC over the namespace those pods land in, and the
// permissions belong to the template, not to this workload. Bind them yourself and
// compose kurly.serviceAccount onto this app, or run external provisioner daemons.
//
// Stateless: the deployment lives in PostgreSQL and the provisioner cache is a
// scratch volume, so replicas scale — coordinating more than one is a licensed
// feature upstream, hence the default of one.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='coder',
  image=defaultImage,
  // The URL workspace agents and browsers reach this server on.
  accessUrl=null,
  // The port the server binds and the Service publishes.
  port=8080,
  // The Secret holding CODER_PG_CONNECTION_URL (kurly mints none), via envFrom.
  // The default pairs with a cnpg-cluster named coder-db.
  secretName='coder',
  replicas=1,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local accessEnv = if accessUrl == null then {} else { CODER_ACCESS_URL: accessUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.envFromSecret(secretName)
  + kurly.env(
    accessEnv {
      // The image binds loopback unless told otherwise, which passes every local
      // check and answers nothing from another pod.
      CODER_HTTP_ADDRESS: '0.0.0.0:' + std.toString(port),
      CODER_CACHE_DIRECTORY: '/home/coder/.cache',
      CODER_TELEMETRY_ENABLE: 'false',
    } + env
  )
  // Every setting is read from a CODER_-prefixed variable, and a Service named
  // coder makes Kubernetes inject CODER_PORT=tcp://…, which the server reads as
  // its own address.
  + kurly.disableServiceLinks()
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Terraform provider plugins and provisioner tarballs are unpacked at runtime,
  // beside the binaries in the image; a scratch there keeps the root filesystem
  // read-only.
  + kurly.scratch('/home/coder/.cache')
  // Coder also writes its own configuration — the tunnel key it generates on
  // first start — into ~/.config, and creating that directory is the FIRST thing
  // `coder server` does. On a read-only root it exits before anything else with
  // a mkdir error, so the directory is a scratch too. It holds generated state
  // rather than anything worth keeping across a restart.
  + kurly.scratch('/home/coder/.config')
  + kurly.scratch('/tmp')
  // The first boot migrates the database before it serves.
  + kurly.startupProbe({ httpGet: { path: '/healthz', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
