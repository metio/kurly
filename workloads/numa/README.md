<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# numa

[numa](https://numa.rs/) — an ad-blocking DNS resolver in a single Rust binary: it forwards (or resolves recursively, with DNSSEC validation), blocks ads and trackers from hosts-style lists, and serves DNS-over-TLS beside plain DNS. A `kurly.http` workload on the official image; its only state is the `numa.toml` it starts from, rendered as a ConfigMap.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local numa = import 'github.com/metio/kurly/workloads/numa/server.libsonnet';
kurly.list(numa())
```

numa answers **DNS on `:53`** (TCP/UDP) and **DoT on `:853`** — both published on the Service, to route as your cluster routes DNS (usually a LoadBalancer). Its dashboard, REST control plane and `/metrics` serve on **`:5380`**; compose an exposure onto that port if you want them. The control plane is authenticated, so `NUMA_API_TOKEN` in the Secret named by `secretName` pins the token — numa mints a fresh one on every start otherwise, and the previous one stops working.

`upstream` and `blocking` are the two tables most deployments change; `settings` merges over the rest of the document (zones, conditional forwarding, per-client policies, DNSSEC), table by table. **DNSSEC validation needs `upstream.mode = 'recursive'`** — a forwarder validates nothing itself. The `.numa` HTTPS proxy is off: it serves LAN discovery behind a certificate authority numa generates and every client device must then trust.

numa keeps no database, so it is stateless and safe at any replica count. Its data directory is a scratch volume, which means a restarted pod regenerates the self-signed DoT certificate; where clients pin that certificate, mount your own and point `dot.cert_path`/`dot.key_path` at it through `settings`.

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
metadata: { name: kurly, namespace: numa }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-numa, namespace: numa }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/numa, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: numa }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-numa, namespace: numa }
spec: { sourceRef: { kind: OCIRepository, name: kurly-numa } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: numa, namespace: numa }
spec:
  serviceAccountName: numa-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/numa/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-numa, importPath: github.com/metio/kurly/workloads/numa }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: numa, namespace: numa }
spec:
  serviceAccountName: numa-deployer
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
        name: numa
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: numa }
```

<!-- END generated: jaas-deploy -->
