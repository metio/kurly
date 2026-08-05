// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// jupyterlab — a JupyterLab server (the web IDE for notebooks, code and data) on
// the Jupyter project's own base-notebook image. A plain composable kurly.http
// workload: the notebooks under /home/jovyan/work live on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local jupyterlab = import 'github.com/metio/kurly/workloads/jupyterlab/server.libsonnet';
//   kurly.list(jupyterlab())
//
// Serves the lab on :8888 — compose an exposure onto it.
//
// AUTH: the server authenticates with a token. Without JUPYTER_TOKEN it mints a
// random one at boot and prints it to the log, which nobody can reach through an
// Ingress — so kurly reads it from a Secret via envFrom. kurly authors no Secret;
// provide one holding JUPYTER_TOKEN.
//
// ANYONE HOLDING THAT TOKEN RUNS ARBITRARY CODE in this pod, as this pod's
// ServiceAccount, on this pod's volume. A notebook server is a shell with a web
// interface; treat the token as a root password and put it behind TLS.
//
// Single writer: one workspace on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='jupyterlab',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The Secret holding JUPYTER_TOKEN (kurly mints none), via envFrom.
  secretName='jupyterlab',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8888)
  + kurly.servicePort(8888)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  // The image runs as jovyan, uid 1000 in the users group (gid 100); pin both and
  // the fsGroup so the workspace volume is writable and the restricted posture
  // admits the pod.
  + kurly.runAs(1000, gid=100, fsGroup=100)
  // The server keeps its runtime state, kernel connection files, settings and
  // caches inside its own home directory, which is part of the image tree.
  + kurly.writableRootFilesystem()
  + kurly.store('/home/jovyan/work', storageSize, storageClass=storageClass)
  // Probe by connection: every HTTP path either redirects to /lab or answers 403
  // without the token, and a probe that follows either kills the pod forever.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
