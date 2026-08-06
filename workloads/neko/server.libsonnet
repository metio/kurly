// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD
//
// neko — a neko server (a virtual browser running in the container, its screen
// and sound streamed to everyone in the room over WebRTC, with shared control of
// the mouse and keyboard). A plain composable kurly.http workload on the official
// Firefox image. Import it and render with kurly.list:
//
//   local neko = import 'github.com/metio/kurly/workloads/neko/server.libsonnet';
//   kurly.list(neko())
//
// Serves the room UI and the signalling WebSocket on :8080 — compose an exposure
// onto it. The media itself does NOT travel over that exposure: it is WebRTC, so
// it needs the multiplexed WebRTC port reachable from the client (see below).
//
// AUTH: the multiuser member provider reads two passwords from the environment.
// kurly authors no Secret; provide one holding
// NEKO_MEMBER_MULTIUSER_USER_PASSWORD and NEKO_MEMBER_MULTIUSER_ADMIN_PASSWORD,
// pulled in via envFrom.
//
// Ephemeral by design: a room is a browser session, not a database. Nothing is
// kept, so this claims no PersistentVolume and is a single-replica Deployment —
// a second replica would be a second, unrelated room behind one address.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='neko',
  image=defaultImage,
  // The Secret holding the multiuser passwords (kurly mints none), via envFrom.
  secretName='neko',
  // Both WebRTC transports are multiplexed onto ONE port, on TCP and on UDP, so
  // the media path is a single port a Service and a firewall can name — the
  // ephemeral port RANGE the alternative needs is neither.
  webrtcPort=59000,
  // The address clients reach the WebRTC port on. WebRTC candidates carry an
  // address, and the pod's own is unroutable from a browser, so without this the
  // room loads and the screen never arrives. There is no sane default: it is the
  // node's or load balancer's public address, which only the deployment knows.
  nat1to1=null,
  // The virtual screen the browser draws on, as WIDTHxHEIGHT@REFRESH.
  screen='1280x720@30',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '3Gi' } },
  // Firefox and GStreamer share decoded frames through /dev/shm, whose default
  // 64Mi a browser exhausts within a few tabs — after which it crashes rather
  // than degrades.
  shmSize='1Gi',
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.extraPort('webrtc-udp', webrtcPort, protocol='UDP')
  + kurly.extraPort('webrtc-tcp', webrtcPort, protocol='TCP')
  + kurly.envFromSecret(secretName)
  + kurly.env(
    {
      NEKO_MEMBER_PROVIDER: 'multiuser',
      NEKO_DESKTOP_SCREEN: screen,
      NEKO_WEBRTC_UDPMUX: std.toString(webrtcPort),
      NEKO_WEBRTC_TCPMUX: std.toString(webrtcPort),
    }
    + (if nat1to1 == null then {} else { NEKO_WEBRTC_NAT1TO1: nat1to1 })
    + env
  )
  // Every setting neko reads is an NEKO_-prefixed environment variable, and a
  // Service named neko makes Kubernetes inject NEKO_PORT as a tcp:// URL — which
  // lands in the same namespace as its own configuration.
  + kurly.disableServiceLinks()
  // supervisord starts as root, brings up the X server, D-Bus and PulseAudio,
  // and drops each program to the neko account. Root to start, the capabilities
  // that account switch needs, and privilege escalation so the setuid call is
  // permitted — the browser itself still runs unprivileged.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // The browser profile lives in /home/neko, which the image populates (a
  // profiles.ini, an extensions directory, an icon theme). A volume mounted
  // there would HIDE all of it, so the root filesystem is writable instead —
  // there is no path that is both writable and the image's own files.
  + kurly.writableRootFilesystem()
  + kurly.scratch('/dev/shm', shmSize)
  // The server answers /health as soon as it binds, but the room is only usable
  // once X, PulseAudio and Firefox are up, which takes tens of seconds on a cold
  // node — a startup probe waits that out without a liveness delay that would
  // then apply forever.
  + kurly.startupProbe({ httpGet: { path: '/health', port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
