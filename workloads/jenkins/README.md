<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# jenkins

[Jenkins](https://www.jenkins.io) — the self-hosted automation server for building, testing and deploying software. A `kurly.http` workload on the official LTS image; `JENKINS_HOME` (jobs, plugins, config, history) on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local jenkins = import 'github.com/metio/kurly/workloads/jenkins/server.libsonnet';
kurly.list(jenkins())
```

Home at `/var/jenkins_home` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the UI on `:8080`; inbound agents connect over the same HTTP port (websocket).

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
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: jenkins }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-jenkins, namespace: jenkins }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/jenkins, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: jenkins }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-jenkins, namespace: jenkins }
spec: { sourceRef: { kind: OCIRepository, name: kurly-jenkins } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: jenkins, namespace: jenkins }
spec:
  serviceAccountName: jenkins-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/jenkins/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-jenkins, importPath: github.com/metio/kurly/workloads/jenkins }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: jenkins, namespace: jenkins }
spec:
  serviceAccountName: jenkins-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: jenkins
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: jenkins }
```

<!-- END generated: jaas-deploy -->
