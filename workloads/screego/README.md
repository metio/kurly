<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# screego

[screego](https://github.com/screego/server) — share your screen with a few
people over WebRTC. A room link and a browser: no account, no plugin, no desktop
client. A plain composable `kurly.http` workload and a stateless one — rooms live
in memory for as long as they are used, so it claims no volume and relaxes nothing
about the hardened defaults.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local screego = import 'github.com/metio/kurly/workloads/screego/server.libsonnet';

kurly.list(screego(externalIp='198.51.100.10'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `screego` | |
| `image` | `ghcr.io/screego/server:1.12.4` | |
| `externalIp` | **required** | the address TURN hands to participants |
| `secretName` | `screego` | supplies `SCREEGO_SECRET` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the app on `:5050`:

```jsonnet
kurly.list([
  screego(externalIp='198.51.100.10')
  + kurly.expose.ownGateway('screen.example.com', 'istio', tls='screego-tls'),
  kurly.certificate('screego-tls', ['screen.example.com'], 'letsencrypt-prod'),
])
```

## `externalIp` is required, and a wrong value is worse than none

screego carries its own TURN server on `:3478` (TCP and UDP), which is what lets
two people on different networks reach each other. TURN has to hand out an address
participants can actually connect to, and screego refuses to start until you name
one:

```text
FTL SCREEGO_EXTERNAL_IP or SCREEGO_TURN_EXTERNAL_IP must be set
```

That refusal is useful, which is why this workload has **no default** for it. A
plausible-looking placeholder would turn a loud startup failure into a much worse
symptom: participants join a room, the app looks entirely healthy, and the shared
screen is simply blank with no error anywhere.

The TURN ports are on the Service but are not HTTP, so an Ingress or HTTPRoute
cannot carry them — give them a `TCPRoute`/`UDPRoute` or a `LoadBalancer`.

## The Secret

`SCREEGO_SECRET` signs session cookies. Left unset, screego generates one at every
start, so each restart logs everybody out.

```shell
kubectl create secret generic screego \
  --from-literal=SCREEGO_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

Screen sharing is open to anyone who can reach the app by default. Set
`SCREEGO_AUTH_MODE` and a users file through `env` if the room should require a
login, or put an authenticating proxy in front.

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
metadata: { name: kurly, namespace: screego }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-screego, namespace: screego }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/screego, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: screego }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-screego, namespace: screego }
spec: { sourceRef: { kind: OCIRepository, name: kurly-screego } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: screego, namespace: screego }
spec:
  serviceAccountName: screego-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/screego/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-screego, importPath: github.com/metio/kurly/workloads/screego }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: screego, namespace: screego }
spec:
  serviceAccountName: screego-deployer
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
        name: screego
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: screego }
```

<!-- END generated: jaas-deploy -->
