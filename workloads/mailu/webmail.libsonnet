// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mailu-webmail — the Mailu webmail client (Roundcube). front proxies /webmail to
// it (:80); it talks to imap and smtp for mail and to admin for authentication.
// One of the six Mailu stages — see the front stage's header and the workload
// README. Optional: drop it (and set WEBMAIL=none on the others via env) if you
// only want IMAP/SMTP clients.
//
//   local webmail = import 'github.com/metio/kurly/workloads/mailu/webmail.libsonnet';
//   kurly.list(webmail(domain='example.com', hostnames=['mail.example.com']))
//
// Keeps its settings and cache at /data on the shared volume. One replica,
// recreated. Runs as root with a writable root filesystem, as every Mailu
// service does.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  namePrefix='mailu',
  name=null,
  image='ghcr.io/mailu/webmail:2024.06',
  domain='example.com',
  hostnames=['mail.example.com'],
  secretName='mailu-secrets',
  storageClaim='mailu-storage',
  subnet='10.0.0.0/8',
  redisAddress='mailu-cache',
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-webmail';
  local mailuEnv = {
    DOMAIN: domain,
    HOSTNAMES: std.join(',', hostnames),
    SUBNET: subnet,
    ADMIN_ADDRESS: namePrefix + '-admin',
    FRONT_ADDRESS: namePrefix + '-front',
    IMAP_ADDRESS: namePrefix + '-imap',
    SMTP_ADDRESS: namePrefix + '-smtp',
    REDIS_ADDRESS: redisAddress,
    WEBMAIL: 'roundcube',
  };

  local storage = {
    deployment+: { spec+: { template+: { spec+: {
      volumes+: [{ name: 'storage', persistentVolumeClaim: { claimName: storageClaim } }],
      containers: [
        container { volumeMounts+: [{ name: 'storage', mountPath: '/data', subPath: 'webmail' }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(mailuEnv)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.hostUsers()
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + storage
