// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wbo — a WBO server (a collaborative whiteboard: open a board URL, draw, and
// everyone else on that URL sees it as you draw). A plain composable kurly.http
// workload; the boards are saved as files on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local wbo = import 'github.com/metio/kurly/workloads/wbo/server.libsonnet';
//   kurly.list(wbo())
//
// Serves the boards on :80 — compose an exposure onto it, and use one that does
// not cut long-lived connections: drawing is streamed over a socket, so a proxy
// with a short idle timeout turns a shared board into one that stops updating
// while still looking connected.
//
// ANYONE WITH A BOARD URL CAN DRAW ON IT. WBO has no accounts and no per-board
// permissions — the URL is the credential. Board names are guessable, so an
// instance reachable from the internet is a shared whiteboard for the internet.
// Put an authenticating proxy in front of it if that is not what you want.
//
// Single writer: boards are files on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) — and also because two pods would each hold their own
// half of the live drawing session.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='wbo',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  // The image already selects uid 1000 and then asks it to bind :80, which an
  // unprivileged process may not do. Granting back the one capability that binding
  // needs is the whole fix — everything else stays dropped, and nothing runs as
  // root.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  + kurly.store('/opt/app/server-data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
