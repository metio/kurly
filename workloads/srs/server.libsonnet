// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// srs — an SRS server (Simple Realtime Server: a live streaming server that
// ingests RTMP, SRT or WebRTC and delivers HLS, HTTP-FLV and WebRTC). A plain
// composable kurly.http workload: the segments it writes live on a
// PersistentVolume, and it needs nothing external. Import it and render with
// kurly.list:
//
//   local srs = import 'github.com/metio/kurly/workloads/srs/server.libsonnet';
//   kurly.list(srs())
//
// Serves HLS and HTTP-FLV on :8080 — compose an exposure onto it. The ingest
// protocols are separate ports on the Service, because none of them is HTTP and
// an Ingress or HTTPRoute cannot carry them:
//
//   1935/TCP   RTMP ingest
//   1985/TCP   the HTTP API
//   8000/UDP   WebRTC
//   10080/UDP  SRT ingest
//
// Route those with a TCPRoute/UDPRoute or a LoadBalancer Service if publishers and
// players are outside the cluster.
//
// Single writer: one volume of recorded segments, so one replica, recreated
// (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

// A starter configuration, replaced wholesale by passing `config`. Three lines of
// it are what make SRS runnable as a container at all, and none of them is a
// preference:
//
//   daemon off      — the shipped conf/srs.conf says `daemon on`, so SRS forks and
//                     the process the container was started for exits. Kubernetes
//                     then restarts it forever.
//   log to console  — the default writes to a file inside the image that nobody
//                     will ever read.
//   pid under /tmp  — the default is ./objs/srs.pid, inside the install tree, and
//                     that tree is read-only here. It cannot simply be shadowed
//                     either: objs/ also holds the `srs` binary.
local defaultConfig = |||
  listen              1935;
  max_connections     1000;
  daemon              off;
  srs_log_tank        console;
  pid                 /tmp/srs.pid;

  http_api {
      enabled         on;
      listen          1985;
  }
  http_server {
      enabled         on;
      listen          8080;
      dir             ./objs/nginx/html;
  }
  rtc_server {
      enabled         on;
      listen          8000;
      candidate       $CANDIDATE;
  }
  srt_server {
      enabled         on;
      listen          10080;
  }

  vhost __defaultVhost__ {
      hls {
          enabled     on;
      }
      http_remux {
          enabled     on;
          mount       [vhost]/[app]/[stream].flv;
      }
      rtc {
          enabled     on;
          rtmp_to_rtc on;
          rtc_to_rtmp on;
      }
  }
|||;

function(
  name='srs',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  config=defaultConfig,
  // The address players are told to reach for WebRTC. WebRTC negotiates a
  // candidate address rather than reusing the connection it was asked over, so
  // this has to be one the player can actually reach — which does not follow from
  // anything kurly can see. Unset, SRS resolves $CANDIDATE to the pod address,
  // which is right for a player inside the cluster and wrong for one outside it.
  candidate=null,
  env={},
  resources={ requests: { cpu: '200m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.extraPort('rtmp', 1935)
  + kurly.extraPort('api', 1985)
  + kurly.extraPort('webrtc', 8000, protocol='UDP')
  + kurly.extraPort('srt', 10080, protocol='UDP')
  // Mounted as a single file over the shipped conf/srs.conf, which leaves the rest
  // of conf/ in place — the image's own command already names that path, so
  // nothing has to override the command to be read.
  + kurly.config({ 'srs.conf': config }, mountPath='/usr/local/srs/conf', subPath=true)
  + (if candidate == null then {} else kurly.env({ CANDIDATE: candidate }))
  + (if env == {} then {} else kurly.env(env))
  // The image runs as root and needs nothing that requires it: every port it binds
  // is above 1024, and the only path it writes is the volume.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp')
  // The segment directory is inside the install tree, which is where SRS's own
  // configuration points; a volume there keeps recordings across restarts without
  // making the rest of the tree writable.
  + kurly.store('/usr/local/srs/objs/nginx/html', storageSize, storageClass=storageClass)
  // The HTTP server answers from the segment directory, which is empty until
  // something is published — so health is a connection check rather than a page.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
