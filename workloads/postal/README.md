<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# postal

[Postal](https://github.com/postalserver/postal) — a full outgoing mail
platform: applications hand it messages over SMTP or its HTTP API, it delivers
them, and it records the fate of every one. Three composable stages on the
official image, backed by an external MySQL/MariaDB and nothing else.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/postal/server.libsonnet';
local worker = import 'github.com/metio/kurly/workloads/postal/worker.libsonnet';
local smtp = import 'github.com/metio/kurly/workloads/postal/smtp.libsonnet';

kurly.list([server(), worker(), smtp()])
```

| Stage | What it is | Port |
|---|---|---|
| `server` | the management interface and HTTP API | `5000` |
| `worker` | delivers the queued mail, retries, webhooks | none |
| `smtp` | accepts mail and bounces | `25` (Service) → `2525` (container) |

Deploy `server` first: it runs `postal initialize`, which creates the schema the
other two read. All three run the same image and differ only in the subcommand.

A Postal install without a worker queues mail and sends none — the web server is
not a mail server on its own.

## No RabbitMQ, no volume

Postal v3 removed the RabbitMQ dependency, and nothing here keeps state on disk.
Everything Postal remembers is in MySQL/MariaDB, so all three stages scale with
`kurly.replicas`.

## Two database logins

The main database holds the organisations, mail servers and routes. The *message*
database is not one schema but one **per mail server**, created by Postal at
runtime from `messageDbPrefix` — so `messageDbUser` needs the right to create
databases on that prefix, which `dbUser` does not need. Point both at the same
server unless you have a reason not to.

## Configuration is environment, not postal.yml

Postal v3 reads every configuration key from a variable named after it —
`main_db.host` is `MAIN_DB_HOST`, `postal.web_hostname` is `POSTAL_WEB_HOSTNAME`
— and it says so and carries on when the config file is absent, which is how it
is run here. Anything not exposed as a parameter goes through `env`.

`webHostname` is the address the instance really answers on: it ends up in every
link Postal mails out, and getting it wrong is not visible until somebody clicks
one.

## Supply the Secret

```shell
kubectl create secret generic postal \
  --from-literal=MAIN_DB_PASSWORD=… \
  --from-literal=MESSAGE_DB_PASSWORD=… \
  --from-literal=RAILS_SECRET_KEY="$(head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-file=SIGNING_KEY=<(openssl genrsa 2048)
```

`SIGNING_KEY` is the odd one out: an RSA private key rather than a password, and
Postal reads it as a **file**, which is why the Secret is mounted at `/secrets`
as well as read into the environment. It signs the DKIM headers on everything
this instance sends, so replacing it invalidates every DNS record already
published for it. Mint it once and keep it.

## Delivering mail off a cluster

Nothing here opens port 25 to the world. The `smtp` stage's Service publishes
`:25` inside the cluster; reaching it from outside is a `LoadBalancer` Service or
a Gateway `TCPRoute`, because SMTP is not HTTP and the exposure recipes emit
HTTP routes. Outbound delivery needs egress on `:25` and a public address whose
reverse DNS, SPF and DKIM records agree with `smtpHostname` — many networks block
outbound `:25` outright, and that is a property of the network rather than of
this workload.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
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
metadata: { name: kurly, namespace: postal }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-postal, namespace: postal }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/postal, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: postal }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-postal, namespace: postal }
spec: { sourceRef: { kind: OCIRepository, name: kurly-postal } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: postal-server, namespace: postal }
spec:
  serviceAccountName: postal-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/postal/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-postal, importPath: github.com/metio/kurly/workloads/postal }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: postal-smtp, namespace: postal }
spec:
  serviceAccountName: postal-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local smtp = import 'github.com/metio/kurly/workloads/postal/smtp.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(smtp())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-postal, importPath: github.com/metio/kurly/workloads/postal }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: postal-worker, namespace: postal }
spec:
  serviceAccountName: postal-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local worker = import 'github.com/metio/kurly/workloads/postal/worker.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(worker())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-postal, importPath: github.com/metio/kurly/workloads/postal }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: postal, namespace: postal }
spec:
  serviceAccountName: postal-deployer
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
        name: postal-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: postal-server }
    - name: smtp
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: postal-smtp
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: postal-smtp }
    - name: worker
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: postal-worker
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: postal-worker }
```

<!-- END generated: jaas-deploy -->
