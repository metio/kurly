// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// zoraxy — a Zoraxy server (an HTTP reverse proxy and forwarding tool driven
// entirely from a web management interface rather than a configuration file). A
// plain composable kurly.http workload keeping its configuration database on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local zoraxy = import 'github.com/metio/kurly/workloads/zoraxy/server.libsonnet';
//   kurly.list(zoraxy())
//
// Serves the management interface on :8000 — compose an exposure onto it.
//
// THE PROXY ITSELF IS NOT WHAT THIS SERVICE EXPOSES: the only port declared here
// is the management interface. Zoraxy opens the listeners for the sites it proxies
// at runtime, from what an operator configures in that interface — :80 and :443
// out of the box, and whatever else it is later told to serve — so which ports
// those are is not known when the manifest is rendered; publish the ones you use
// by composing kurly.extraPort and an exposure of your own.
//
// It runs as root with a writable root filesystem, and neither is decoration: the
// image's entrypoint runs update-ca-certificates before it starts anything, which
// rewrites /etc/ssl/certs; that command is run with check=True, so on a read-only
// filesystem — or as a user that may not write there — the entrypoint exits 1 and
// the pod never starts. Capabilities stay dropped and privilege escalation stays
// off.
//
// The container-integration and mDNS discovery the image enables by default are
// switched off here: DOCKER=true has Zoraxy look for a Docker socket that a pod
// does not have, and MDNS=true multicasts on a network where nothing answers.
//
// Single writer: one configuration database on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='zoraxy',
  image=defaultImage,
  storageSize='2Gi',
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
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env({
    // The entrypoint turns these into the server's flags.
    PORT: '8000',
    DOCKER: 'false',
    MDNS: 'false',
    ZEROTIER: 'false',
  } + env)
  // The entrypoint rewrites /etc/ssl/certs before starting the server, and fails
  // the container when it cannot.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // Zoraxy reads PORT for its listen port, and a Service in the same namespace
  // whose name yields PORT_* variables is exactly the shape that has taken other
  // workloads down; nothing here needs the injected links.
  + kurly.disableServiceLinks()
  // Its working directory and the database, the certificates and the site
  // definitions in it.
  + kurly.store('/opt/zoraxy/config', storageSize, storageClass=storageClass)
  // The management interface answers / with a login page it redirects to, so both
  // probes ask the port rather than a path.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
