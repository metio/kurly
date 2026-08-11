// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// dagu — a workflow engine that runs DAGs declared in YAML, with a web UI to
// launch, watch and retry them. A plain composable kurly.http workload: dagu
// keeps its DAG definitions, run history and logs in files under DAGU_HOME on a
// PersistentVolume and needs no external database or queue. Import it and render
// with kurly.list:
//
//   local dagu = import 'github.com/metio/kurly/workloads/dagu/server.libsonnet';
//   kurly.list(dagu())
//
// Serves the web UI and API on :8080 — compose an exposure onto it.
//
// ENTRYPOINT: the image's entrypoint runs as root to reconcile the dagu user's
// uid with PUID/PGID and then drops privileges with sudo, which needs a writable
// /etc and a root container. The command here calls the dagu binary directly
// instead, so the hardened posture stands: unprivileged uid, read-only root
// filesystem, all capabilities dropped. `fsGroup` is what makes DAGU_HOME
// writable, taking over the job the entrypoint's chown was doing.
//
// WHAT IT RUNS: `dagu start-all` is the scheduler AND the web server in one
// process, and DAG steps execute as child processes IN THIS CONTAINER — so a DAG
// can only use what the image ships. Steps that need their own tools belong in
// dagu's Kubernetes or SSH executors rather than in a bigger image here.
//
// Single writer: the scheduler owns the run history on a ReadWriteOnce volume, so
// one replica, recreated (never rolled) to keep two schedulers off the same runs.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='dagu',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.command(['dagu'])
  + kurly.args(['start-all'])
  + kurly.env({ DAGU_HOME: '/var/lib/dagu', DAGU_HOST: '0.0.0.0', DAGU_PORT: '8080', HOME: '/var/lib/dagu' } + env)
  // The uid the image's own dagu user carries.
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.store('/var/lib/dagu', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/api/v2/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/v2/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
