<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# configarr

[Configarr](https://configarr.de/) — keeps the quality profiles, custom formats
and naming settings of a Sonarr/Radarr-style application in step with TRaSH
Guides and with a configuration you keep in Git. A composable `kurly.cron`
workload, because that is what it is: it runs, reconciles, and exits.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local configarr = import 'github.com/metio/kurly/workloads/configarr/sync.libsonnet';

kurly.list(configarr(
  services={
    sonarr: { base_url: 'http://sonarr:8989', api_key: '!secret SONARR_API_KEY' },
    radarr: { base_url: 'http://radarr:7878', api_key: '!secret RADARR_API_KEY' },
  },
  secretName='configarr',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `configarr` | |
| `image` | the pinned upstream image | |
| `schedule` | `0 4 * * *` | daily at 04:00 |
| `services` | `{}` | one entry per managed application |
| `config` | `{}` | merged over the rendered `config.yml` |
| `secretName` | none | a Secret holding `secrets.yml` |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

## It writes to the applications it points at

Every run replaces the profiles and formats it manages in Sonarr or Radarr with
what the configuration says. That is the whole point, and it means a hand-made
change in the web UI is undone at the next run rather than merged — the
configuration here is the source of truth, or Configarr should not be pointed at
that instance.

## API keys do not belong in the ConfigMap

Configarr resolves `!secret NAME` in its `config.yml` from a `secrets.yml`, which
is mounted here from the Secret `secretName` names:

```shell
kubectl create secret generic configarr --from-file=secrets.yml
```

Writing a key inline would put it in a ConfigMap, readable by anything that can
read ConfigMaps in the namespace.

The TRaSH Guides repository is cloned on each run, so the pod needs egress to
GitHub.

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
metadata: { name: kurly, namespace: configarr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-configarr, namespace: configarr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/configarr, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: configarr }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-configarr, namespace: configarr }
spec: { sourceRef: { kind: OCIRepository, name: kurly-configarr } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: configarr, namespace: configarr }
spec:
  serviceAccountName: configarr-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local sync = import 'github.com/metio/kurly/workloads/configarr/sync.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(sync())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-configarr, importPath: github.com/metio/kurly/workloads/configarr }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: configarr, namespace: configarr }
spec:
  serviceAccountName: configarr-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: sync
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: configarr
```

<!-- END generated: jaas-deploy -->
