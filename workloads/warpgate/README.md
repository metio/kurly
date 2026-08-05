<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# warpgate

[Warpgate](https://github.com/warp-tech/warpgate) — a smart SSH, HTTPS and
database bastion. Users connect with an ordinary client, authenticate once, and
Warpgate proxies them to the targets they are allowed while recording the session.
A plain composable `kurly.http` workload: configuration, SQLite database, SSH host
keys and any recordings live on one PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local warpgate = import 'github.com/metio/kurly/workloads/warpgate/server.libsonnet';

kurly.list(warpgate())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `warpgate` | |
| `image` | `ghcr.io/warp-tech/warpgate:0.27.2` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/data` |
| `httpPort` / `sshPort` | `8888` / `2222` | |
| `secretName` | `warpgate` | supplies `WARPGATE_ADMIN_PASSWORD` |
| `recordSessions` | `false` | see below |
| `resources` / `labels` / `annotations` | | |

The admin UI and HTTPS proxy are on `:8888`; SSH is a second Service port on
`:2222` and is not HTTP, so give it a `TCPRoute` or a `LoadBalancer` rather than
an Ingress.

## The setup runs once, and that is the point

`warpgate run` refuses to start without a configuration file, and the only thing
that writes one is a setup step — interactive by default, which a pod cannot
answer. So an init container runs `unattended-setup`, guarded by a test for the
file it produces.

That guard is not an optimisation. **The same step mints the SSH host keys**, so
rerunning it on every restart would issue new ones and break every client that had
already trusted the old — which looks exactly like the attack `known_hosts` exists
to detect. It is also why this is one replica: two instances with different host
keys fail the same way.

`WARPGATE_ADMIN_PASSWORD` is read **once**, by that setup step, to create the first
administrator. Changing the Secret afterwards does not change the password, which
by then lives hashed in Warpgate's own database — use `warpgate recover-access` for
that.

## Session recording is off by default

`recordSessions` writes the contents of every proxied session to the volume. That
is a storage decision and a privacy one, and neither is kurly's to make on
somebody's behalf — turn it on deliberately, and size the volume for it.

## Probes

Both probes run the image's own `warpgate healthcheck` subcommand. It knows what a
healthy Warpgate is better than a request to a page does, and the alternative is
awkward: the HTTP port speaks TLS, so an `httpGet` probe would have to be told to
use HTTPS and would still only prove a listener is up.

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
metadata: { name: kurly, namespace: warpgate }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-warpgate, namespace: warpgate }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/warpgate, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: warpgate }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-warpgate, namespace: warpgate }
spec: { sourceRef: { kind: OCIRepository, name: kurly-warpgate } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: warpgate, namespace: warpgate }
spec:
  serviceAccountName: warpgate-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/warpgate/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-warpgate, importPath: github.com/metio/kurly/workloads/warpgate }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: warpgate, namespace: warpgate }
spec:
  serviceAccountName: warpgate-deployer
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
        name: warpgate
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: warpgate }
```

<!-- END generated: jaas-deploy -->
