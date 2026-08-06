// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// livebook — a Livebook server (interactive and collaborative code notebooks for
// Elixir). A plain composable kurly.http workload on the official image: the
// notebooks and Livebook's own configuration live on a PersistentVolume. Import it
// and render with kurly.list:
//
//   local livebook = import 'github.com/metio/kurly/workloads/livebook/server.libsonnet';
//   kurly.list(livebook())
//
// Serves the notebook UI on :8080 — compose an exposure onto it.
//
// AUTH: without a password Livebook prints a one-time token into the pod log and
// accepts nothing else, which on a rolling replacement means the link everyone has
// stops working. kurly authors no Secret; provide one holding LIVEBOOK_PASSWORD
// (at least 12 characters) and LIVEBOOK_SECRET_KEY_BASE (at least 64), pulled in
// via envFrom.
//
// A NOTEBOOK RUNS ARBITRARY CODE INSIDE THIS POD, with the pod's ServiceAccount,
// network and volume. Anyone who can sign in has a shell in the cluster — treat
// access to it as you would access to a node.
//
// Single writer: the notebooks live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) rather than two pods writing the same files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='livebook',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The Secret holding LIVEBOOK_PASSWORD and LIVEBOOK_SECRET_KEY_BASE (kurly mints
  // none), via envFrom.
  secretName='livebook',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env({
    // The image ships LIVEBOOK_IP=:: — a dual-stack bind that fails on an
    // IPv4-only pod network, so bind the IPv4 wildcard explicitly.
    LIVEBOOK_IP: '0.0.0.0',
    LIVEBOOK_PORT: '8080',
    // Notebooks, and the hubs and secrets Livebook remembers, both on the volume:
    // LIVEBOOK_DATA_PATH otherwise lands under HOME, which is scratch here and
    // would take every configured hub with it on a restart.
    LIVEBOOK_HOME: '/data',
    // The VOLUME ROOT, not a subdirectory of it. Livebook checks that
    // LIVEBOOK_DATA_PATH is a writable directory and refuses to start if it is
    // not — it does not create one. A fresh PersistentVolume contains nothing,
    // so `/data/.livebook` is absent on first boot and the container exits with
    // "expected LIVEBOOK_DATA_PATH to be a writable directory", which reads like
    // a permissions problem and is an absent-directory one. The mount point
    // itself is created by Kubernetes and made group-writable by fsGroup, so it
    // is the one path guaranteed to be there.
    LIVEBOOK_DATA_PATH: '/data',
    // An Elixir release writes its runtime vm.args and cookie into the release
    // tree unless RELEASE_TMP names somewhere else; the root filesystem is
    // read-only, so name the scratch.
    RELEASE_TMP: '/tmp',
  } + env)
  // The image sets no USER and chmods its tree world-readable, so pin an
  // unprivileged uid and an fsGroup that owns the volume.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // HOME is where mix, hex and the runtime keep their caches; a notebook
  // installing a dependency writes there.
  + kurly.scratch('/home/livebook', '1Gi')
  + kurly.scratch('/tmp', '256Mi')
  // The BEAM boots, compiles the notebook runtime and only then serves; a
  // liveness probe alone would restart it mid-start.
  + kurly.startupProbe({ httpGet: { path: '/public/health', port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/public/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/public/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
