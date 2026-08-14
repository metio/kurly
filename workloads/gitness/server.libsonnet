// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gitness — Harness Open Source (the project Gitness was renamed to): git
// repositories, an artifact registry and a web interface in one binary, with
// SQLite underneath so it needs no database beside it. A plain composable
// kurly.http workload. Import it and render with kurly.list:
//
//   local gitness = import 'github.com/metio/kurly/workloads/gitness/server.libsonnet';
//   kurly.list(gitness())
//
// Serves the web interface and API on :3000 and git-over-SSH on :3022 — compose
// an exposure onto the HTTP port; SSH is a raw TCP protocol and needs a TCP route
// of its own, so publishing the web interface does not publish git-over-SSH.
//
// PIPELINES AND GITSPACES NEED A DOCKER DAEMON, WHICH A CLUSTER DOES NOT GIVE IT.
// The binary drives a Docker API to run pipeline steps and development
// environments, and there is no daemon inside the pod. Repositories, the
// registry, pull requests and the web interface all work; running a pipeline
// reports that it cannot reach Docker. `gitspaces=false` turns off the half that
// advertises itself and cannot work, rather than leaving a button that fails.
//
// IT PHONES HOME BY DEFAULT. The image sets a metrics endpoint that reports usage
// to the project; `metrics=false` writes the variable that turns it off.
//
// Single writer: the SQLite database, the git repositories and the registry blobs
// all live on one ReadWriteOnce volume, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='gitness',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  // The URL a browser reaches this at; the clone URLs it prints are built from
  // it, so a wrong one hands every user a git remote that does not resolve.
  url=null,
  // Development environments. Off, because they need a Docker daemon this pod
  // does not have.
  gitspaces=false,
  // Usage reporting to the project. Off.
  metrics=false,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.extraPort('ssh', 3022)
  + kurly.env(
    {
      GITNESS_GITSPACE_ENABLE: if gitspaces then 'true' else 'false',
      GITNESS_METRIC_ENABLED: if metrics then 'true' else 'false',
    }
    + (if url != null then { GITNESS_URL_BASE: url } else {})
    + env
  )
  // The image runs as root and owns nothing that needs it; fsGroup makes the
  // repositories, the SQLite database and the registry blobs writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '1Gi')
  // A first start creates the database and the git root before it listens, and a
  // large registry takes longer still, so the wait is a startup probe rather than
  // a longer liveness delay.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
