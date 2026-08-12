// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// collabora-online — the editing engine behind a self-hosted office suite: it
// renders and edits documents, spreadsheets and presentations for a file
// application that embeds it over WOPI. A plain composable kurly.http workload:
// documents live in the application it serves, not here, so it claims no volume.
// Import it and render with kurly.list:
//
//   local collabora = import 'github.com/metio/kurly/workloads/collabora-online/server.libsonnet';
//   kurly.list(collabora(wopiHosts=['nextcloud\\.example\\.com']))
//
// Serves on :9980 — compose an exposure onto it.
//
// IT IS HALF AN APPLICATION. Collabora Online edits documents somebody else
// stores: Nextcloud, ownCloud, Seafile or anything speaking WOPI. On its own it
// serves an admin console and a discovery endpoint and nothing a user wants. The
// file application is where a deployment starts.
//
// `wopiHosts` ARE REGULAR EXPRESSIONS, AND THE DOTS MATTER. The entries become an
// allow-list of the hosts permitted to embed this editor, matched as regexes — so
// an unescaped dot matches any character and `files.example.com` also admits
// `filesXexample.com`. Escape them. An empty list admits nobody, which is the
// safe default and not a working deployment.
//
// THE SANDBOX IS OFF BY DEFAULT, AND THAT IS A REAL TRADE. Collabora edits each
// document in a forked process and can put that process in a chroot of its own —
// which needs CAP_SYS_ADMIN, a capability close enough to root that granting it
// costs more than the sandbox buys inside a container that is already isolated by
// the kubelet. So `security.capabilities` is disabled and no capability is added.
// `sandbox=true` turns it back on for a deployment that wants defence in depth and
// accepts a container holding SYS_ADMIN and MKNOD; the catalogue's security score
// reflects the difference.
//
// Memory scales with the number of documents open at once rather than with users,
// so the limit here is a starting point for a small team.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='collabora-online',
  image=defaultImage,
  replicas=1,
  // The hosts allowed to embed this editor, as REGULAR EXPRESSIONS — escape the
  // dots. Empty admits nobody.
  wopiHosts=[],
  // The public URL the editor is reached at, for the links it generates.
  serverName=null,
  // A Secret carrying the admin console credentials, read through envFrom.
  secretName=null,
  // Run each document in a chroot of its own. Needs SYS_ADMIN — see the header.
  sandbox=false,
  // Extra coolwsd settings, as the --o: flags the image reads from env.
  extraParams=[],
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(9980)
  + kurly.servicePort(9980)
  + kurly.env(
    { aliasgroup1: std.join('|', wopiHosts) }
    + (if serverName != null then { server_name: serverName } else {})
    + (
      local params = (if sandbox then [] else ['--o:security.capabilities=false']) + extraParams;
      if params != [] then { extra_params: std.join(' ', params) } else {}
    )
    + env
  )
  // The uid the image already runs as.
  + kurly.runAs(1001, gid=1001)
  // Each document is edited in a forked, chrooted process, which the engine
  // builds under these paths at runtime — so they are writable rather than part
  // of the read-only image.
  + kurly.scratch('/opt/cool/child-roots', '2Gi')
  + kurly.scratch('/opt/cool/cache', '1Gi')
  + kurly.scratch('/tmp', '1Gi')
  // Only when the sandbox is asked for: building a chroot is a mount-namespace
  // operation the dropped-ALL default forbids. Granted by name rather than by
  // relaxing the whole posture, and not granted at all by default.
  + (if sandbox then kurly.addCapabilities(['SYS_ADMIN', 'MKNOD']) else {})
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
