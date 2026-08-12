// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docs/y-provider — the collaboration server behind Docs: it carries the Yjs
// document updates between everyone editing the same page, and converts documents
// on export. A composable kurly.http workload. Import it and render alongside the
// backend and frontend.
//
// Serves on :4444, over WebSocket.
//
// WITHOUT IT, EDITING LOOKS FINE UNTIL TWO PEOPLE TRY IT. Documents open and save
// through the backend either way; what disappears is the live part — two people
// on one page each see their own typing and neither sees the other, with nothing
// in a log to explain it. That is the failure this stage exists to prevent, so
// deploy it with the other two.
//
// THE COLLABORATION STATE IS IN MEMORY. y-provider holds the in-flight document
// for as long as somebody has it open and hands the result to the backend; a
// restart drops the unsaved part of an open session, which is why one replica is
// the arrangement that behaves predictably — two would hold different copies of
// the same document.
//
// It authenticates the backend's calls with a shared secret, so its Secret and
// the backend's must agree.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './y-provider.image', '\n');

function(
  name='docs-y-provider',
  image=defaultImage,
  // The backend it hands finished documents to.
  backendHost='docs-backend',
  backendPort=8000,
  // A Secret carrying Y_PROVIDER_API_KEY and COLLABORATION_SERVER_SECRET, which
  // must match the backend's.
  secretName='docs',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  // One replica: the in-flight document lives in this process — see the header.
  + kurly.replicas(1)
  + kurly.port(4444)
  + kurly.servicePort(4444)
  + kurly.env({
    PORT: '4444',
    COLLABORATION_SERVER_ORIGIN: 'http://' + backendHost + ':' + backendPort,
  } + env)
  + kurly.envFromSecret(secretName)
  // The uid and gid the image already runs as.
  + kurly.runAs(1001, gid=127)
  + kurly.scratch('/tmp', '256Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
