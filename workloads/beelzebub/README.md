<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# beelzebub

[Beelzebub](https://github.com/beelzebub-labs/beelzebub) — a low-code honeypot:
it pretends to be services an attacker wants to find (SSH, HTTP, databases),
records what they try, and answers convincingly enough to keep them going. A
plain composable `kurly.http` workload: every impersonated service is a YAML
file, rendered here as a ConfigMap, and events go to stdout or an external sink.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local beelzebub = import 'github.com/metio/kurly/workloads/beelzebub/honeypot.libsonnet';

kurly.list(beelzebub(services={
  'http-8080': {
    apiVersion: 'v1',
    protocol: 'http',
    address: ':8080',
    description: 'Apache 2.4',
    commands: [{ regex: '.*', handler: '<html><body>It works</body></html>', statusCode: 200 }],
  },
  'ssh-2222': { apiVersion: 'v1', protocol: 'ssh', address: ':2222', description: 'OpenSSH 8.9' },
}))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `beelzebub` | |
| `image` | the pinned upstream image | |
| `replicas` | `1` | each replica sees only the attacks that reach it |
| `services` | one HTTP service on `:8080` | one entry per impersonated service |
| `env` | `{}` | Beelzebub's `BEELZEBUB_*` global settings |
| `resources` / `labels` / `annotations` | | |

## A honeypot is meant to be attacked

Which makes it the one workload in a namespace you must assume is compromised. It
runs with the hardened default — unprivileged, read-only root filesystem, no
capabilities — and it belongs in a namespace of its own with a NetworkPolicy that
lets it reach nothing inside the cluster:

```jsonnet
beelzebub() + kurly.network.kubernetes(allowTo=[])
```

Beelzebub emulates its services rather than running the real ones, so a break-out
is a break-out of a Go process, not of sshd. That is a reason for care, not for
confidence.

## Ports follow the services

Each service names its own `address`, and the ports published on the Service are
derived from those addresses — there is no list to keep in step by hand. The
first service's port is the one probed. A service wanting a port below 1024 needs
`kurly.addCapabilities(['NET_BIND_SERVICE'])`, or better, an exposure that maps
22 to something unprivileged here.

Global settings come from the `BEELZEBUB_*` environment overrides rather than a
core configuration file: a missing core file is not an error, and kurly gives a
workload one ConfigMap, which the services use.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

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
metadata: { name: kurly, namespace: beelzebub }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-beelzebub, namespace: beelzebub }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/beelzebub, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: beelzebub }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-beelzebub, namespace: beelzebub }
spec: { sourceRef: { kind: OCIRepository, name: kurly-beelzebub } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: beelzebub, namespace: beelzebub }
spec:
  serviceAccountName: beelzebub-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local honeypot = import 'github.com/metio/kurly/workloads/beelzebub/honeypot.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(honeypot())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-beelzebub, importPath: github.com/metio/kurly/workloads/beelzebub }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: beelzebub, namespace: beelzebub }
spec:
  serviceAccountName: beelzebub-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: honeypot
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: beelzebub
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: beelzebub }
```

<!-- END generated: jaas-deploy -->
