// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// note-mark — a Note Mark server (a small web-based Markdown notes app: a Go
// binary serving both the API and the compiled frontend). A plain composable
// kurly.http workload: notes, uploaded assets and the SQLite database live on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local notemark = import 'github.com/metio/kurly/workloads/note-mark/server.libsonnet';
//   kurly.list(notemark(publicUrl='https://notes.example.com'))
//
// Serves the app and its API on :8080 — compose an exposure onto it.
//
// PUBLIC_URL IS DEPLOYMENT-SPECIFIC and the app refuses to start without a valid
// one, so it defaults to a localhost URL that boots and is wrong everywhere it is
// really deployed — set it to the host the browser reaches, with no trailing
// slash (the app validates that too).
//
// SECRET: AUTH_TOKEN__SECRET signs the session tokens and is base64 of at least
// 32 bytes. kurly authors no Secret; provide one holding that key, pulled in via
// envFrom.
//
// Single writer: one SQLite database and one asset tree on a ReadWriteOnce
// volume, so one replica, recreated (never rolled) — two pods writing the same
// database is not a thing SQLite will sort out for you.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='note-mark',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // The URL a browser reaches this instance at, without a trailing slash.
  publicUrl='http://localhost:8080',
  // The Secret holding AUTH_TOKEN__SECRET (kurly mints none), via envFrom.
  secretName='note-mark',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    // The image binds 127.0.0.1 only if this is unset — the default in the
    // binary, not in the image, and a pod nothing can reach passes every probe
    // that talks to itself.
    BIND__HOST: '0.0.0.0',
    BIND__PORT: '8080',
    DATA_PATH: '/data',
    STATIC_PATH: '/static',
    PUBLIC_URL: publicUrl,
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  // A static Go binary on a distroless base: it needs no account of its own, and
  // fsGroup is what gives it the volume.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // Probe by connection: the app answers / with the single-page frontend, but
  // every API path under it is authenticated.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
