<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# liwan

[Liwan](https://liwan.dev/) — privacy-first web analytics: a one-line script per
site, no cookies and no persistent identifiers, with everything kept in an
embedded DuckDB beside it. A plain composable `kurly.http` workload; that
database lives on a PersistentVolume, so there is no external database to stand
up.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local liwan = import 'github.com/metio/kurly/workloads/liwan/server.libsonnet';

kurly.list(liwan(baseUrl='https://analytics.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `liwan` | |
| `image` | `explodingcamera/liwan:1.6.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/data` |
| `baseUrl` | unset | the public URL, scheme included |
| `logLevel` | `info` | |
| `disableFavicons` | `true` | referrer icons come from DuckDuckGo |
| `env` / `resources` / `labels` / `annotations` | | |

## Set `baseUrl` before you publish it

Liwan does not refuse to start without one — it falls back to
`http://localhost:9042`, which is why no wrong default is baked in here. That
fallback decides the origin the tracking script is served for and whether session
cookies are marked secure, so an instance reachable at a real name and still
carrying it authenticates over an insecure cookie and rejects the events its own
script sends.

## The setup link is in the log

While no user exists, Liwan mints a one-time onboarding token and logs the link
that redeems it — `<baseUrl>/setup?t=…` — and that is the only way to create the
first administrator through the dashboard. It is built from `baseUrl`, so an
unset one logs a link to `localhost`; the token itself is the part that matters
and can be pasted onto the real host. A fresh token is minted on every start
until an account exists, so a restart is not a lockout. The binary's own
`add-user` command is the other route.

## Behind an ingress, every visitor looks like one visitor

Liwan reads the visitor's address from the connection. Every request through an
ingress controller arrives from that controller, so without

```jsonnet
env={
  LIWAN_TRUSTED_PROXIES: '10.0.0.0/8',
  LIWAN_CLIENT_IP_HEADERS: 'x-forwarded-for',
}
```

the whole internet is grouped as a single visitor. Name only the proxies you
actually run: a header from a client you do not trust is a header the client
chose.

## GeoIP is off

Country breakdowns need either a MaxMind database
(`LIWAN_MAXMIND_ACCOUNT_ID` + `LIWAN_MAXMIND_LICENSE_KEY`) or headers a CDN in
front already sets (`LIWAN_GEOIP_HEADERS` understands `cloudflare`, `cloudfront`,
`netlify`, `vercel` and `akamai`). Neither is assumed here.

## One writer

One DuckDB database on a ReadWriteOnce volume, so one replica, recreated rather
than rolled. Two processes opening the same database file is not a thing DuckDB
sorts out for you.

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
metadata: { name: kurly, namespace: liwan }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-liwan, namespace: liwan }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/liwan, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: liwan }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-liwan, namespace: liwan }
spec: { sourceRef: { kind: OCIRepository, name: kurly-liwan } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: liwan, namespace: liwan }
spec:
  serviceAccountName: liwan-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/liwan/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-liwan, importPath: github.com/metio/kurly/workloads/liwan }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: liwan, namespace: liwan }
spec:
  serviceAccountName: liwan-deployer
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
        name: liwan
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: liwan }
```

<!-- END generated: jaas-deploy -->
