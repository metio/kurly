// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mailu-smtp — the Mailu MTA (Postfix). It relays mail between the edge, the
// filter, and the store: front hands it inbound mail, rspamd screens it, and
// dovecot receives local delivery over LMTP. One of the six Mailu stages — see
// the front stage's header and the workload README.
//
//   local smtp = import 'github.com/metio/kurly/workloads/mailu/smtp.libsonnet';
//   kurly.list(smtp(domain='example.com', hostnames=['mail.example.com']))
//
// The Postfix queue is transient (Mailu does not persist it); only user overrides
// live on the shared volume. One replica, recreated. Runs as root with a writable
// root filesystem, as every Mailu service does.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

// The submission ports front relays to Postfix on, beyond the primary :25 that
// kurly.http names 'http'.
local postfixPorts = [
  { name: 'smtps', port: 465 },
  { name: 'submission', port: 587 },
];

function(
  namePrefix='mailu',
  name=null,
  image='ghcr.io/mailu/postfix:2024.06',
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
  local resolvedName = if name != null then name else namePrefix + '-smtp';
  local mailuEnv = {
    DOMAIN: domain,
    HOSTNAMES: std.join(',', hostnames),
    SUBNET: subnet,
    ADMIN_ADDRESS: namePrefix + '-admin',
    IMAP_ADDRESS: namePrefix + '-imap',
    ANTISPAM_ADDRESS: namePrefix + '-antispam:11332',
    REDIS_ADDRESS: redisAddress,
  } + (if resolverAddress == '' then {} else { RESOLVER_ADDRESS: resolverAddress });

  local storage = {
    deployment+: { spec+: { template+: { spec+: {
      volumes+: [{ name: 'storage', persistentVolumeClaim: { claimName: storageClaim } }],
      containers: [
        container {
          ports+: [{ containerPort: p.port, name: p.name, protocol: 'TCP' } for p in postfixPorts],
          volumeMounts+: [{ name: 'storage', mountPath: '/overrides', subPath: 'overrides/postfix' }],
        }
        for container in super.containers
      ],
    } } } },
    service+: { spec+: { ports+: [{ name: p.name, port: p.port, targetPort: p.name, protocol: 'TCP' } for p in postfixPorts] } },
  };

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(25)
  + kurly.servicePort(25)
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
