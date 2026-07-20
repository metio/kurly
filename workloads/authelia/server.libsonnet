// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// authelia — an Authelia server (a self-hosted, open-source authentication and authorization
// gateway that adds single sign-on and two-factor authentication in front of your other apps,
// via a reverse proxy's forward-auth). A plain composable kurly.http workload on the official
// image. Its whole behaviour is its configuration.yml, mounted as a ConfigMap; with the
// default SQLite storage its database and notifications live on a PersistentVolume. Import it,
// pass your config, and render with kurly.list:
//
//   local authelia = import 'github.com/metio/kurly/workloads/authelia/server.libsonnet';
//   kurly.list(authelia(config=myAutheliaConfig))
//
// Serves its API and portal on :9091 — compose an exposure onto it, and wire your reverse
// proxy's forward-auth at it.
//
// CONFIG IS THE WORKLOAD: `config` is Authelia's own configuration.yml schema (server,
// authentication_backend, access_control, session, storage, notifier), mounted verbatim —
// kurly does not model it. The default is a minimal skeleton that MUST be completed for your
// domain, identity backend and access rules before it is useful.
//
// SECRETS: Authelia needs several secrets (the session secret, storage encryption key, JWT
// secret, and any OIDC/SMTP credentials), supplied as AUTHELIA_*_FILE or AUTHELIA_* env. kurly
// authors no Secret; provide one holding them, pulled in via envFrom.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');

// A minimal skeleton — complete it for your domain, identity backend and access rules.
local defaultConfig = {
  theme: 'light',
  server: { address: 'tcp://0.0.0.0:9091' },
  log: { level: 'info' },
  authentication_backend: { file: { path: '/config/users_database.yml' } },
  access_control: { default_policy: 'one_factor' },
  session: { cookies: [{ domain: 'example.com', authelia_url: 'https://auth.example.com' }] },
  storage: { 'local': { path: '/config/db.sqlite3' } },
  notifier: { filesystem: { filename: '/config/notification.txt' } },
};

function(
  name='authelia',
  image='ghcr.io/authelia/authelia:4.39.5',
  storageSize='1Gi',
  storageClass=null,
  config=defaultConfig,
  secretName='authelia-secrets',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9091)
  + kurly.servicePort(9091)
  + kurly.config({ 'configuration.yml': std.manifestYamlDoc(config) }, mountPath='/config/generated')
  + kurly.envFromSecret(secretName)
  + kurly.env({ X_AUTHELIA_CONFIG: '/config/generated/configuration.yml' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
