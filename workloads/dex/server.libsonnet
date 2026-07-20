// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// dex — a Dex server (an OpenID Connect / OAuth 2.0 identity provider that federates
// to upstream connectors: LDAP, SAML, GitHub, Google, …). A plain composable
// kurly.http workload on the official image: with the SQLite storage backend its
// state lives on a PersistentVolume, so it needs no external database. Import it and
// render with kurly.list:
//
//   local dex = import 'github.com/metio/kurly/workloads/dex/server.libsonnet';
//   kurly.list(dex())
//
// Serves the OIDC endpoints on :5556 — compose an exposure onto it.
//
// CONFIGURATION: Dex is entirely driven by a config.yaml (issuer, storage,
// connectors, staticClients). It carries secrets (client secrets, connector
// credentials), so mount it from a Secret — kurly authors none — at /etc/dex. The
// default storage is SQLite on the volume; point it at PostgreSQL in the config to
// scale past the single writer, or use the `kubernetes` backend with kurly.rbac.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='dex',
  image='ghcr.io/dexidp/dex:v2.45.1',
  storageSize='1Gi',
  storageClass=null,
  // The Secret holding config.yaml (kurly mints none), mounted at /etc/dex.
  configSecret='dex-config',
  env={},
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5556)
  + kurly.servicePort(5556)
  + kurly.command(['dex', 'serve', '/etc/dex/config.yaml'])
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/dex', storageSize, storageClass=storageClass)
  + kurly.secretMount(configSecret, '/etc/dex')
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
