// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// vaultwarden — a Vaultwarden server (a lightweight, Bitwarden-compatible password
// manager written in Rust). A plain composable kurly.http workload: it keeps its
// vault, attachments, and the JWT signing key in a SQLite database on a
// PersistentVolume by default, so it needs no external database. Import it and
// render with kurly.list:
//
//   local vaultwarden = import 'github.com/metio/kurly/workloads/vaultwarden/server.libsonnet';
//   kurly.list(vaultwarden(domain='https://vault.example.com'))
//
// Serves the web vault and API on :8080 — compose an exposure onto it. Set
// `domain` to the public URL: WebAuthn/passkeys, attachments, and email links all
// need to know it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file. Point DATABASE_URL at an
// external PostgreSQL through `env` to scale past that (the connection string then
// carries a password — supply it from a Secret, kurly mints none).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='vaultwarden',
  image='docker.io/vaultwarden/server:1.36.0',
  storageSize='2Gi',
  storageClass=null,
  // The public URL clients reach Vaultwarden at. Required for WebAuthn/passkeys,
  // attachment links, and email; left null, some features degrade.
  domain=null,
  // New-user registration. Off by default — a password manager open to the world
  // is rarely what you want; turn it on to bootstrap, then off.
  signupsAllowed=false,
  // Extra Vaultwarden settings (ADMIN_TOKEN for the admin panel, SMTP_*,
  // DATABASE_URL for external Postgres, …), merged over the below. ADMIN_TOKEN and
  // any DATABASE_URL password should come from a Secret, not a literal here.
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    // The image binds :80 as root by default; move it to an unprivileged port so
    // the restricted, non-root posture can serve it.
    ROCKET_PORT: '8080',
    DATA_FOLDER: '/data',
    SIGNUPS_ALLOWED: (if signupsAllowed then 'true' else 'false'),
  } + (if domain == null then {} else { DOMAIN: domain });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(baseEnv + env)
  // The image ships no non-root user; pin one and its fsGroup so the data volume
  // is writable and the restricted posture admits the pod.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // Rocket writes temp files for uploads; keep the root filesystem read-only with
  // a scratch /tmp.
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/alive', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/alive', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
