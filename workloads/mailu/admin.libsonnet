// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mailu-admin — the Mailu administration service: the web admin UI, the internal
// API the other services query for users/domains/aliases, and the SQLite database
// and DKIM keys behind them. front proxies /admin to it; postfix, dovecot, and
// rspamd read their configuration from its API. One of the six Mailu stages —
// see the front stage's header and the workload README for the whole picture.
//
//   local admin = import 'github.com/metio/kurly/workloads/mailu/admin.libsonnet';
//   kurly.list(admin(domain='example.com', hostnames=['mail.example.com']))
//
// Holds the authoritative state on the shared volume (the DB at /data, DKIM keys
// at /dkim that rspamd also reads), so it is one replica, recreated. Runs as root
// with a writable root filesystem, as every Mailu service does.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  namePrefix='mailu',
  name=null,
  image='ghcr.io/mailu/admin:2024.06',
  domain='example.com',
  hostnames=['mail.example.com'],
  secretName='mailu-secrets',
  storageClaim='mailu-storage',
  subnet='10.0.0.0/8',
  redisAddress='mailu-cache',
  resolverAddress='',
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-admin';
  local mailuEnv = {
    DOMAIN: domain,
    HOSTNAMES: std.join(',', hostnames),
    SUBNET: subnet,
    ADMIN_ADDRESS: resolvedName,
    SMTP_ADDRESS: namePrefix + '-smtp',
    IMAP_ADDRESS: namePrefix + '-imap',
    ANTISPAM_ADDRESS: namePrefix + '-antispam:11332',
    WEBMAIL_ADDRESS: namePrefix + '-webmail',
    REDIS_ADDRESS: redisAddress,
    DB_FLAVOR: 'sqlite',
  } + (if resolverAddress == '' then {} else { RESOLVER_ADDRESS: resolverAddress });

  local storage = {
    deployment+: { spec+: { template+: { spec+: {
      volumes+: [{ name: 'storage', persistentVolumeClaim: { claimName: storageClaim } }],
      containers: [
        container { volumeMounts+: [
          { name: 'storage', mountPath: '/data', subPath: 'data' },
          { name: 'storage', mountPath: '/dkim', subPath: 'dkim' },
        ] }
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
