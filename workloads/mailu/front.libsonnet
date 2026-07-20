// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mailu-front — the Mailu edge (an nginx reverse proxy). It terminates the mail
// protocols and the web UI and proxies them to the other Mailu services: SMTP
// (25/465/587), IMAP (143/993), POP3 (110/995), ManageSieve (4190), and HTTP
// (80/443) for the admin and webmail apps. It is the one Mailu service you expose
// to the world.
//
// Mailu is a coordinated set of services that share one SECRET_KEY, one domain,
// and one ReadWriteMany volume; run all six stages (front, admin, imap, smtp,
// antispam, webmail) together, pointed at the same namePrefix, secretName, and
// storageClaim, plus a Redis (the valkey workload). See the workload README.
//
//   local front = import 'github.com/metio/kurly/workloads/mailu/front.libsonnet';
//   kurly.list(front(domain='example.com', hostnames=['mail.example.com']))
//
// Mailu's images run as root (they bind privileged ports and setuid) and template
// their configuration into the root filesystem at boot, so this workload relaxes
// kurly's non-root and read-only-rootfs defaults — the hardening a mail server
// cannot keep. It still drops all capabilities, blocks privilege escalation, and
// runs under its own ServiceAccount.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

// The public mail and web ports the edge terminates, beyond the primary :80 that
// kurly.http names 'http'. Each rides onto both the container and the Service via
// kurly.extraPort.
local edgePorts = [
  { name: 'smtp', port: 25 },
  { name: 'smtps', port: 465 },
  { name: 'submission', port: 587 },
  { name: 'pop3', port: 110 },
  { name: 'pop3s', port: 995 },
  { name: 'imap', port: 143 },
  { name: 'imaps', port: 993 },
  { name: 'sieve', port: 4190 },
  { name: 'https', port: 443 },
];

function(
  namePrefix='mailu',
  name=null,
  image='ghcr.io/mailu/nginx:2024.06',
  domain='example.com',
  hostnames=['mail.example.com'],
  secretName='mailu-secrets',
  storageClaim='mailu-storage',
  subnet='10.0.0.0/8',
  redisAddress='mailu-cache',
  resolverAddress='',
  tlsFlavor='mail',
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-front';
  local mailuEnv = {
    DOMAIN: domain,
    HOSTNAMES: std.join(',', hostnames),
    SUBNET: subnet,
    TLS_FLAVOR: tlsFlavor,
    ADMIN_ADDRESS: namePrefix + '-admin',
    SMTP_ADDRESS: namePrefix + '-smtp',
    IMAP_ADDRESS: namePrefix + '-imap',
    ANTISPAM_ADDRESS: namePrefix + '-antispam:11332',
    WEBMAIL_ADDRESS: namePrefix + '-webmail',
    REDIS_ADDRESS: redisAddress,
  } + (if resolverAddress == '' then {} else { RESOLVER_ADDRESS: resolverAddress });

  // The shared TLS-cert directory, mounted from the coordinated Mailu volume. The
  // ports are composed as features below; this patch is only the /certs mount.
  local certVolume = {
    deployment+: { spec+: { template+: { spec+: {
      volumes+: [{ name: 'storage', persistentVolumeClaim: { claimName: storageClaim } }],
      containers: [
        container { volumeMounts+: [{ name: 'storage', mountPath: '/certs', subPath: 'certs' }] }
        for container in super.containers
      ],
    } } } },
  };

  std.foldl(
    function(app, p) app + kurly.extraPort(p.name, p.port),
    edgePorts,
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
    + certVolume,
  )
