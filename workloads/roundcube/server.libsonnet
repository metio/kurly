// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// roundcube — a Roundcube server (a browser-based IMAP webmail client). A plain
// composable kurly.http workload on the official image: it connects to an external
// IMAP/SMTP mail server and keeps its own state in a SQLite database on a
// PersistentVolume, so it needs no external database. Import it and render with
// kurly.list:
//
//   local roundcube = import 'github.com/metio/kurly/workloads/roundcube/server.libsonnet';
//   kurly.list(roundcube(imapHost='ssl://mail.example.com:993', smtpHost='tls://mail.example.com:587'))
//
// Serves the webmail UI on :80 — compose an exposure onto it. Point it at the mailu
// workload (or any IMAP/SMTP server) via imapHost/smtpHost.
//
// The Apache + PHP image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: the SQLite database (contacts, preferences) lives on a ReadWriteOnce
// volume, so one replica, recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='roundcube',
  image='docker.io/roundcube/roundcubemail:1.7.2-apache',
  storageSize='1Gi',
  storageClass=null,
  // The IMAP and SMTP servers Roundcube connects users to (required).
  imapHost=null,
  smtpHost=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
                    ROUNDCUBEMAIL_DB_TYPE: 'sqlite',
                    ROUNDCUBEMAIL_DB_DIR: '/var/roundcube/db',
                  }
                  + (if imapHost == null then {} else { ROUNDCUBEMAIL_DEFAULT_HOST: imapHost })
                  + (if smtpHost == null then {} else { ROUNDCUBEMAIL_SMTP_SERVER: smtpHost });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/roundcube/db', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
