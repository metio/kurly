// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// MediaMTX — a real-time media server and proxy: it ingests a live stream over
// one protocol and republishes it over the others (RTSP, RTMP, HLS, WebRTC,
// SRT). A plain composable kurly.http workload on the official image; its
// mediamtx.yml is the only state it needs, rendered as a ConfigMap. Import it
// and render with kurly.list:
//
//   local mediamtx = import 'github.com/metio/kurly/workloads/mediamtx/server.libsonnet';
//   kurly.list(mediamtx())
//
// PORTS: the HTTP port is HLS (:8888), which is the one an Ingress or HTTPRoute
// can carry, so compose an exposure onto it for browser playback. Everything
// else is published beside it on the Service and is NOT HTTP: RTSP :8554 (plus
// the RTP/RTCP pair :8000/:8001 UDP that the UDP transport needs), RTMP :1935,
// WebRTC :8889 with its ICE/UDP mux on :8189, SRT :8890 UDP. Route those with a
// LoadBalancer — an HTTP proxy cannot.
//
// WEBRTC needs a candidate address a browser can actually reach. In a cluster
// the pod IP is not one, so a deployment that publishes WebRTC beyond the
// cluster sets webrtcAdditionalHosts in `config` to the address its
// LoadBalancer answers on. Playback over HLS has no such requirement.
//
// CONFIG: `config` is mediamtx.yml, rendered whole and passed as the server's
// argument. The defaults enable the ingest and playback protocols, the control
// API on :9997 and Prometheus metrics on :9998, and accept any path name
// (`all_others`). Replace or extend it for authentication, named paths, or an
// on-demand source. No Secret: the default config carries no credential —
// mediamtx is UNAUTHENTICATED as it stands, so anybody who reaches a port can
// publish and read streams. Decide that before exposing it.
//
// Stateless: nothing is written to disk, so no PersistentVolume, and the
// content is per-connection rather than shared — a second replica is a second
// server with its own streams, not a bigger one. Compose kurly.store and set
// the record options in `config` if recordings should be kept.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='mediamtx',
  image=defaultImage,
  replicas=1,
  // mediamtx.yml, rendered whole. Every address is written EXPLICITLY rather
  // than left to mediamtx's defaults, because the numbers here and the ports
  // the Service declares have to be the same ones — a stage may only declare a
  // port its image actually binds.
  config={
    logLevel: 'info',
    api: true,
    apiAddress: ':9997',
    metrics: true,
    metricsAddress: ':9998',
    rtsp: true,
    rtspAddress: ':8554',
    rtpAddress: ':8000',
    rtcpAddress: ':8001',
    rtmp: true,
    rtmpAddress: ':1935',
    hls: true,
    hlsAddress: ':8888',
    webrtc: true,
    webrtcAddress: ':8889',
    webrtcLocalUDPAddress: ':8189',
    srt: true,
    srtAddress: ':8890',
    // MoQ is on by default and would bind :8892 and :8893 that no port here
    // declares, over a TLS certificate it mints for itself at startup. It is
    // experimental and no browser reaches it through an ordinary Service, so it
    // is off; turn it on together with the ports it needs.
    moq: false,
    // mediamtx refuses to start without a paths section; all_others accepts any
    // path name a publisher invents.
    paths: { all_others: {} },
  },
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  // HLS is the HTTP half and the only port an Ingress or HTTPRoute can carry.
  + kurly.port(8888)
  + kurly.servicePort(8888)
  + kurly.extraPort('rtsp', 8554)
  + kurly.extraPort('rtp', 8000, protocol='UDP')
  + kurly.extraPort('rtcp', 8001, protocol='UDP')
  + kurly.extraPort('rtmp', 1935)
  + kurly.extraPort('webrtc', 8889)
  + kurly.extraPort('webrtc-ice', 8189, protocol='UDP')
  + kurly.extraPort('srt', 8890, protocol='UDP')
  + kurly.extraPort('api', 9997)
  + kurly.extraPort('metrics', 9998)
  // The image is FROM scratch around a static binary and sets no user, so it
  // would otherwise run as uid 0; nothing in it is owned by a particular uid,
  // so any unprivileged one serves. Every port it binds is above 1024, so the
  // restricted posture stands with no capability granted back.
  + kurly.runAs(1000, gid=1000)
  // mediamtx takes the config path as its argument; the image's own
  // /mediamtx.yml is left alone.
  + kurly.config({ 'mediamtx.yml': std.manifestYamlDoc(config, quote_keys=false) })
  + kurly.args(['/etc/config/mediamtx.yml'])
  // Probed by connection on the HLS port: mediamtx answers 404 on every path
  // that is not a live stream, and a stream only exists once somebody
  // publishes one, so a path probe would restart a perfectly healthy server.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
