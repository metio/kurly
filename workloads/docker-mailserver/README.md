<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# docker-mailserver

[Docker Mailserver](https://github.com/docker-mailserver/docker-mailserver) — a
full mail server in one container: Postfix for SMTP, Dovecot for IMAP, plus the
spam filtering, virus scanning, DKIM signing and TLS that make mail from it
deliverable. A composable `kurly.http` workload whose primary port is `:25`.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dms = import 'github.com/metio/kurly/workloads/docker-mailserver/server.libsonnet';

kurly.list(dms(hostname='mail.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `docker-mailserver` | |
| `image` | `ghcr.io/docker-mailserver/docker-mailserver:15.1.0` | |
| `hostname` | `mail.example.com` | SMTP banner, greeting name, certificate subject |
| `mailStorageSize` | `20Gi` | `/var/mail` — the maildirs |
| `stateStorageSize` | `5Gi` | `/var/mail-state` — spam corpus, DKIM keys, account databases |
| `configStorageSize` | `1Gi` | `/tmp/docker-mailserver` — what `setup` writes |
| `storageClass` | cluster default | all three volumes |
| `accountsSecret` | none | a Secret holding a `postfix-accounts.cf` |
| `env` / `resources` / `labels` / `annotations` | | |

## Reaching it

| Port | Protocol |
|---|---|
| 25 | SMTP |
| 465 | submissions (implicit TLS) |
| 587 | submission (STARTTLS) |
| 143 | IMAP (STARTTLS) |
| 993 | IMAPS |

None of these are HTTP, so an Ingress or an HTTPRoute cannot carry them. Give the
Service a `LoadBalancer` type (`kurly.serviceType('LoadBalancer')`) or a
NodePort, and point the domain's MX record at the address it gets.

## The hostname is not cosmetic

Receiving mail servers compare the greeting name, the reverse DNS of the sending
address and the certificate the connection presents. `hostname` must be the fully
qualified name the MX record points at, and that name must resolve back to the
address mail leaves from — otherwise outbound mail is refused as spam whatever
else is configured. Many networks also block outbound `:25` entirely.

## It refuses to start without an account

There are no default accounts, and this is not a task for afterwards: the
container waits two minutes for a mailbox to exist and then shuts itself down.
There are two ways to give it one, and they exclude each other.

Leave `accountsSecret` unset and create the account from inside the pod within
that window:

```shell
kubectl exec -it deploy/docker-mailserver -- setup email add you@example.com
```

It lands in the configuration volume and survives a restart, and every later
account, alias and DKIM key is managed the same way.

Or name a Secret holding a `postfix-accounts.cf` — one line per mailbox, in the
`address|{SCHEME}hash` format `setup` itself writes:

```shell
kubectl create secret generic docker-mailserver --from-file=postfix-accounts.cf
```

It mounts read-only over the file on the configuration volume, so `setup email
add` refuses and the accounts are whatever the Secret says — which is what a
deployment reconciled from git wants. kurly authors no such Secret: a mailbox
list with password hashes in it is a document a deployment writes.

## Less hardened, deliberately

`supervisord` starts Postfix, Dovecot and the filters as root and each of them
drops to its own account; the entrypoint chowns the mail volumes on first boot,
and both daemons bind privileged ports. The root filesystem is writable because
queues, sockets, pid files and generated configuration all live inside the
image's own tree.

`fail2ban` is switched off. It manipulates the pod's own netfilter rules, which
needs `NET_ADMIN`, and the address it would ban is the shared one everything
behind the cluster's egress path arrives from.

## Persistence

Maildirs on a ReadWriteOnce volume, so this is **one replica, recreated** (never
rolled). Two Postfix instances delivering into the same maildirs is not something
either of them arbitrates.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: docker-mailserver }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-docker-mailserver, namespace: docker-mailserver }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/docker-mailserver, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: docker-mailserver }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-docker-mailserver, namespace: docker-mailserver }
spec: { sourceRef: { kind: OCIRepository, name: kurly-docker-mailserver } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: docker-mailserver, namespace: docker-mailserver }
spec:
  serviceAccountName: docker-mailserver-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/docker-mailserver/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-docker-mailserver, importPath: github.com/metio/kurly/workloads/docker-mailserver }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: docker-mailserver, namespace: docker-mailserver }
spec:
  serviceAccountName: docker-mailserver-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: docker-mailserver
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: docker-mailserver }
```

<!-- END generated: jaas-deploy -->
