// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docker-mailserver — a full mail server in one container: Postfix for SMTP,
// Dovecot for IMAP, plus the spam and virus filtering, DKIM signing and TLS that
// make mail from it deliverable. A composable kurly.http workload — the primary
// port is :25 — with the mailboxes, the service state and the account
// configuration on PersistentVolumes. Import it and render with kurly.list:
//
//   local dms = import 'github.com/metio/kurly/workloads/docker-mailserver/server.libsonnet';
//   kurly.list(dms(hostname='mail.example.com'))
//
// Serves SMTP on :25, submission on :587 and :465, and IMAP on :143 and :993.
// These are not HTTP, so an Ingress or HTTPRoute cannot carry them — reach them
// with a LoadBalancer Service (kurly.serviceType) or a NodePort, and give the
// pod the public hostname its banner and certificates must match.
//
// IT REFUSES TO START WITHOUT AN ACCOUNT. Docker Mailserver waits two minutes
// for one and then shuts the container down, so an account is a prerequisite of
// booting rather than a first task afterwards. There are two ways to give it
// one, and they exclude each other:
//
//   - leave accountsSecret null and run `setup email add <address>` inside the
//     pod within that window. The account lands in the configuration volume and
//     survives a restart, and every later account is added the same way.
//   - name a Secret holding a postfix-accounts.cf — one `address|{SCHEME}hash`
//     line per account, the format `setup` itself writes. It mounts read-only,
//     so `setup email add` will refuse: accounts are then whatever the Secret
//     says, which is what a deployment reconciled from git wants.
//
// The hostname is not cosmetic. Receiving mail servers compare the greeting name,
// the reverse DNS of the sending address and the certificate; `hostname` must be
// the fully qualified name the MX record points at, or outbound mail is refused
// as spam whatever else is configured.
//
// Single writer: maildirs on ReadWriteOnce volumes, so one replica, recreated
// (never rolled) — two Postfix instances delivering into the same maildirs is
// not a thing either of them arbitrates.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='docker-mailserver',
  image=defaultImage,
  // The fully qualified name of this mail server, used as the SMTP banner, the
  // greeting name and the certificate subject.
  hostname='mail.example.com',
  // The maildirs — the mail server's primary data.
  mailStorageSize='20Gi',
  // Service state kept across restarts: the spam filter's learned corpus, the
  // DKIM keys, the account databases the setup command writes.
  stateStorageSize='5Gi',
  // The configuration directory the `setup` command reads and writes.
  configStorageSize='1Gi',
  storageClass=null,
  // A Secret holding a postfix-accounts.cf, mounted over the one on the
  // configuration volume. Null leaves account management to the setup command
  // inside the pod.
  accountsSecret=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // Postfix on the primary port, then submission and the IMAP ports beside it.
  + kurly.port(25)
  + kurly.servicePort(25)
  + kurly.extraPort('submission', 587)
  + kurly.extraPort('submissions', 465)
  + kurly.extraPort('imap', 143)
  + kurly.extraPort('imaps', 993)
  + kurly.env(
    {
      // The pod's own hostname is a generated pod name, which is never the name
      // mail must come from, so the banner name is stated outright.
      OVERRIDE_HOSTNAME: hostname,
      // Logs belong to the pod's stdout, not to a file inside the container.
      LOG_LEVEL: 'info',
      // fail2ban manipulates the pod's own netfilter rules, which needs
      // NET_ADMIN and bans the shared NAT address of everything behind the
      // cluster's ingress path rather than an individual sender.
      ENABLE_FAIL2BAN: '0',
    } + env
  )
  // supervisord starts Postfix, Dovecot and the filters as root and each of them
  // drops to its own account; the entrypoint also chowns the mail volumes on
  // first boot, and Postfix and Dovecot bind the privileged mail ports.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // Postfix, Dovecot and supervisord write their queues, sockets, pid files and
  // generated configuration all over the image's own tree.
  + kurly.writableRootFilesystem()
  // A Service named after the workload would inject DOCKER_MAILSERVER_PORT and
  // friends into an environment the setup scripts read wholesale.
  + kurly.disableServiceLinks()
  + kurly.store('/var/mail', mailStorageSize, storageClass=storageClass)
  + kurly.store('/var/mail-state', stateStorageSize, storageClass=storageClass)
  + kurly.store('/tmp/docker-mailserver', configStorageSize, storageClass=storageClass)
  + (
    if accountsSecret == null then {}
    else kurly.secretMount(
      accountsSecret,
      '/tmp/docker-mailserver/postfix-accounts.cf',
      subPath='postfix-accounts.cf',
    )
  )
  // Postfix and Dovecot answer on the wire and have no health endpoint; the
  // first boot generates certificates and Rspamd/OpenDKIM state before either
  // listens, so the start is given room rather than the liveness probe.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
