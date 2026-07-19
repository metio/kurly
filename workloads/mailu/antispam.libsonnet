// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mailu-antispam — the Mailu filter (Rspamd). Postfix and Dovecot screen mail
// through it (:11332), it serves its own web UI (:11334), and it signs outbound
// mail with the DKIM keys admin generates on the shared volume. One of the six
// Mailu stages — see the front stage's header and the workload README.
//
//   local antispam = import 'github.com/metio/kurly/workloads/mailu/antispam.libsonnet';
//   kurly.list(antispam(domain='example.com', hostnames=['mail.example.com']))
//
// Its learned state (Bayes, fuzzy, greylist) lives at /var/lib/rspamd on the
// shared volume, so it is one replica, recreated. Runs as root with a writable
// root filesystem, as every Mailu service does.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

// The proxy port (:11332) is primary and named 'http' by kurly.http; the web/
// controller port (:11334) rides alongside.
local controllerPort = { name: 'controller', port: 11334 };

function(
  namePrefix='mailu',
  name=null,
  image='ghcr.io/mailu/rspamd:2024.06',
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
  local resolvedName = if name != null then name else namePrefix + '-antispam';
  local mailuEnv = {
    DOMAIN: domain,
    HOSTNAMES: std.join(',', hostnames),
    SUBNET: subnet,
    ADMIN_ADDRESS: namePrefix + '-admin',
    REDIS_ADDRESS: redisAddress,
  } + (if resolverAddress == '' then {} else { RESOLVER_ADDRESS: resolverAddress });

  local storage = {
    deployment+: { spec+: { template+: { spec+: {
      volumes+: [{ name: 'storage', persistentVolumeClaim: { claimName: storageClaim } }],
      containers: [
        container {
          ports+: [{ containerPort: controllerPort.port, name: controllerPort.name, protocol: 'TCP' }],
          volumeMounts+: [
            { name: 'storage', mountPath: '/var/lib/rspamd', subPath: 'filter' },
            { name: 'storage', mountPath: '/dkim', subPath: 'dkim' },
          ],
        }
        for container in super.containers
      ],
    } } } },
    service+: { spec+: { ports+: [{ name: controllerPort.name, port: controllerPort.port, targetPort: controllerPort.name, protocol: 'TCP' }] } },
  };

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(11332)
  + kurly.servicePort(11332)
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
