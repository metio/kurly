// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mailu-imap — the Mailu mail store (Dovecot). It holds the maildirs on the shared
// volume and serves IMAP/POP3 to front and LMTP delivery to postfix. One of the
// six Mailu stages — see the front stage's header and the workload README.
//
//   local imap = import 'github.com/metio/kurly/workloads/mailu/imap.libsonnet';
//   kurly.list(imap(domain='example.com', hostnames=['mail.example.com']))
//
// The maildirs at /mail are the mail server's primary data, so this is one
// replica, recreated. Runs as root with a writable root filesystem, as every
// Mailu service does.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

// The ports front and postfix reach Dovecot on, beyond the primary :143 that
// kurly.http names 'http'.
local dovecotPorts = [
  { name: 'imaps', port: 993 },
  { name: 'pop3', port: 110 },
  { name: 'pop3s', port: 995 },
  { name: 'sieve', port: 4190 },
  { name: 'lmtp', port: 2525 },
];

function(
  namePrefix='mailu',
  name=null,
  image='ghcr.io/mailu/dovecot:2024.06',
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
  local resolvedName = if name != null then name else namePrefix + '-imap';
  local mailuEnv = {
    DOMAIN: domain,
    HOSTNAMES: std.join(',', hostnames),
    SUBNET: subnet,
    ADMIN_ADDRESS: namePrefix + '-admin',
    ANTISPAM_ADDRESS: namePrefix + '-antispam:11332',
    WEBMAIL_ADDRESS: namePrefix + '-webmail',
    REDIS_ADDRESS: redisAddress,
  } + (if resolverAddress == '' then {} else { RESOLVER_ADDRESS: resolverAddress });

  local storage = {
    deployment+: { spec+: { template+: { spec+: {
      volumes+: [{ name: 'storage', persistentVolumeClaim: { claimName: storageClaim } }],
      containers: [
        container {
          ports+: [{ containerPort: p.port, name: p.name, protocol: 'TCP' } for p in dovecotPorts],
          volumeMounts+: [
            { name: 'storage', mountPath: '/mail', subPath: 'mail' },
            { name: 'storage', mountPath: '/overrides', subPath: 'overrides/dovecot' },
          ],
        }
        for container in super.containers
      ],
    } } } },
    service+: { spec+: { ports+: [{ name: p.name, port: p.port, targetPort: p.name, protocol: 'TCP' } for p in dovecotPorts] } },
  };

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(143)
  + kurly.servicePort(143)
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
