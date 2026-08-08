<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# vinyl-cache

[vinyl-cache](https://vinyl-cache.org/) — a caching HTTP reverse proxy: it sits in front of an application, keeps the responses it is allowed to keep in memory, and serves the next request for them itself. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local vinyl = import 'github.com/metio/kurly/workloads/vinyl-cache/server.libsonnet';
kurly.list(vinyl(backendUrl='http://my-app.my-namespace.svc:8080'))
```

Serves on `:8080`, behind a Service on `:80`.

Without a `backendUrl` it is not a proxy: the configuration the image ships answers every request from a static page baked into the image, so a deployment that forgets it comes up healthy and caches nothing anybody asked for. The URL must carry a scheme — the shipped configuration refuses to load without one, which fails the startup rather than proxying somewhere unintended.

`vcl` is the Varnish Configuration Language, mounted verbatim at `/etc/varnish-vcl/default.vcl` and named through `VARNISH_VCL_FILE` — kurly does not model it. It is mounted *beside* the image's own `/etc/varnish`, never over it, so the `hit-miss.vcl` and `verbose_builtin.vcl` snippets stay on the default include path and a configuration that includes them still loads.

The cache is memory, and the two numbers have to agree: `cacheSize` is the store the server is given, and the container's memory limit has to leave room for it plus the process itself. Raising one without the other is how the cache gets the pod OOM-killed under exactly the load it was added for.

The cache starts cold and nothing is kept on disk, so the workload scales horizontally — at the price of each replica holding its own copy of the cache.

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
metadata: { name: kurly, namespace: vinyl-cache }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-vinyl-cache, namespace: vinyl-cache }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/vinyl-cache, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: vinyl-cache }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-vinyl-cache, namespace: vinyl-cache }
spec: { sourceRef: { kind: OCIRepository, name: kurly-vinyl-cache } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: vinyl-cache, namespace: vinyl-cache }
spec:
  serviceAccountName: vinyl-cache-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/vinyl-cache/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-vinyl-cache, importPath: github.com/metio/kurly/workloads/vinyl-cache }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: vinyl-cache, namespace: vinyl-cache }
spec:
  serviceAccountName: vinyl-cache-deployer
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
        name: vinyl-cache
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: vinyl-cache }
```

<!-- END generated: jaas-deploy -->
