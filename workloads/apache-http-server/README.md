<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# apache-http-server

[Apache HTTP Server](https://github.com/apache/httpd) — httpd: static files, rewriting, proxying and authentication through its module system. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local httpd = import 'github.com/metio/kurly/workloads/apache-http-server/server.libsonnet';
kurly.list(httpd())
```

`config` is httpd's own configuration language, mounted verbatim at `/etc/httpd/httpd.conf` and named on the command line with `-f` — kurly does not model it. It is mounted *beside* the image's `/usr/local/apache2/conf`, never over it, so `TypesConfig conf/mime.types` and any `Include conf/extra/…` still resolve.

The configuration the image ships cannot be used as it stands: it listens on `:80`, which an unprivileged uid cannot bind, and it writes the pid file, the scoreboard and both logs under `/usr/local/apache2/logs`, which the read-only root filesystem refuses. The default here is a complete minimal configuration instead — `:8080`, `DefaultRuntimeDir` and the pid file on the scratch at `/tmp`, both logs to the container's own stdout and stderr.

The served directory is the image's `htdocs`, so the workload keeps nothing and scales horizontally. To serve your own site, compose a `kurly.config` or a `kurly.store` onto it and point `documentRoot` at the mount.

Serves on `:8080`.

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
metadata: { name: kurly, namespace: apache-http-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-apache-http-server, namespace: apache-http-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/apache-http-server, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: apache-http-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-apache-http-server, namespace: apache-http-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly-apache-http-server } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: apache-http-server, namespace: apache-http-server }
spec:
  serviceAccountName: apache-http-server-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/apache-http-server/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-apache-http-server, importPath: github.com/metio/kurly/workloads/apache-http-server }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: apache-http-server, namespace: apache-http-server }
spec:
  serviceAccountName: apache-http-server-deployer
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
        name: apache-http-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: apache-http-server }
```

<!-- END generated: jaas-deploy -->
