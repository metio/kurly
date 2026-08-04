<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# centrifugo

[Centrifugo](https://github.com/centrifugal/centrifugo) — a real-time messaging
server. Browsers and apps subscribe over WebSocket, SSE or HTTP-streaming, and
your backend publishes to them over an HTTP or GRPC API, so you do not write and
operate a socket server of your own.

A plain composable `kurly.http` workload, and an unusual one here: it is
**stateless**. Channel history and presence live in memory or in Redis, never on
disk, so this workload claims no PersistentVolume at all.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local centrifugo = import 'github.com/metio/kurly/workloads/centrifugo/server.libsonnet';

kurly.list(centrifugo())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `centrifugo` | |
| `image` | `centrifugo/centrifugo:v6.9.1` | |
| `secretName` | `centrifugo` | token key, API key, admin credentials |
| `admin` | `false` | the administrative web UI |
| `env` | `{}` | any `CENTRIFUGO_*` setting |
| `resources` / `labels` / `annotations` | | |

Serves clients and the API on `:8000`:

```jsonnet
kurly.list([
  centrifugo()
  + kurly.expose.ownGateway('realtime.example.com', 'istio', tls='centrifugo-tls'),
  kurly.certificate('centrifugo-tls', ['realtime.example.com'], 'letsencrypt-prod'),
])
```

**Use an exposure that does not cut long-lived connections.** WebSocket and SSE
are the entire point of this workload, so a proxy with a short idle timeout turns
it into a reconnect loop that still looks healthy from the outside.

## The Secret

Everything in it authenticates somebody, so kurly mints none of it:

| key | what it protects |
|---|---|
| `CENTRIFUGO_CLIENT_TOKEN_HMAC_SECRET_KEY` | the JWTs your backend issues to clients |
| `CENTRIFUGO_HTTP_API_KEY` | the publish API |

```shell
kubectl create secret generic centrifugo \
  --from-literal=CENTRIFUGO_CLIENT_TOKEN_HMAC_SECRET_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=CENTRIFUGO_HTTP_API_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

Turning on `admin` needs `CENTRIFUGO_ADMIN_PASSWORD` and
`CENTRIFUGO_ADMIN_SECRET` in the same Secret. It is off by default because it is a
full administrative surface answering on the same port as the client traffic an
exposure publishes.

## One replica is a correctness bound, not caution

Without a broker, each instance knows only its own subscribers: a message
published to one pod never reaches clients connected to another. A scaled-out
deployment looks perfectly healthy and delivers a fraction of its traffic.

Point it at Redis — `CENTRIFUGO_BROKER_ENABLED` plus the Redis address through
`env` — and it scales horizontally.

## Configuration names follow the flags, not the endpoints

Centrifugo's environment variables mirror its command-line flags, so the health
endpoint is `CENTRIFUGO_HEALTH_ENABLED` (from `--health.enabled`) even though it
is served by the HTTP server. Guessing `CENTRIFUGO_HTTP_SERVER_HEALTH_ENABLED`
produces a **warning in the log and nothing else** — the server starts, reports
itself fine, and the probe then fails against an endpoint that was never switched
on. Check `centrifugo --help` for a name before assuming it.

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
metadata: { name: kurly, namespace: centrifugo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-centrifugo, namespace: centrifugo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/centrifugo, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: centrifugo }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-centrifugo, namespace: centrifugo }
spec: { sourceRef: { kind: OCIRepository, name: kurly-centrifugo } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: centrifugo, namespace: centrifugo }
spec:
  serviceAccountName: centrifugo-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/centrifugo/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-centrifugo, importPath: github.com/metio/kurly/workloads/centrifugo }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: centrifugo, namespace: centrifugo }
spec:
  serviceAccountName: centrifugo-deployer
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
        name: centrifugo
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: centrifugo }
```

<!-- END generated: jaas-deploy -->
