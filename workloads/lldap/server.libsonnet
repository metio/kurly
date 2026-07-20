// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// lldap — an LLDAP server (a light LDAP implementation for authentication: a simple,
// opinionated user/group directory with a friendly web UI, a lightweight stand-in for
// OpenLDAP that apps authenticate against). A plain composable kurly.http workload on the
// official image; with the default SQLite backend its directory lives on a
// PersistentVolume. Import it, point it at its secrets, and render with kurly.list:
//
//   local lldap = import 'github.com/metio/kurly/workloads/lldap/server.libsonnet';
//   kurly.list(lldap())
//
// Serves the web UI and API on :17170 — compose an exposure onto it.
//
// LDAP: apps bind over LDAP on :3890, a separate port this HTTP workload does not expose.
// Add a Service for it (a raw `+` patch) so clients can authenticate.
//
// SECRETS: LLDAP needs LLDAP_JWT_SECRET and LLDAP_LDAP_USER_PASS (the admin password),
// and typically LLDAP_LDAP_BASE_DN. kurly authors no Secret; provide one holding them,
// pulled in via envFrom. Point it at an external PostgreSQL/MySQL (LLDAP_DATABASE_URL) to
// scale past the single SQLite writer.
//
// Single writer: the SQLite directory lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='lldap',
  image='docker.io/lldap/lldap:v0.6.3',
  storageSize='1Gi',
  storageClass=null,
  baseDn=null,
  // The Secret holding LLDAP_JWT_SECRET and LLDAP_LDAP_USER_PASS (kurly mints none), via
  // envFrom.
  secretName='lldap-secrets',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if baseDn == null then {} else { LLDAP_LDAP_BASE_DN: baseDn };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(17170)
  + kurly.servicePort(17170)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
