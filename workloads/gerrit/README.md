<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gerrit

[Gerrit Code Review](https://www.gerritcodereview.com/) — git hosting where every
push becomes a change others review and vote on before it lands. A plain
composable `kurly.http` workload on the official image, with the site's
persistent directories on PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gerrit = import 'github.com/metio/kurly/workloads/gerrit/server.libsonnet';

kurly.list(gerrit(canonicalWebUrl='https://review.example.com/'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `gerrit` | |
| `image` | `gerritcodereview/gerrit:3.14.2` | |
| `storageSize` | `20Gi` | `/var/gerrit/git`, the repositories |
| `indexSize` | `5Gi` | `/var/gerrit/index` |
| `dbSize` | `2Gi` | `/var/gerrit/db` |
| `etcSize` | `1Gi` | `/var/gerrit/etc`, the configuration and its keys |
| `storageClass` | cluster default | |
| `canonicalWebUrl` | | the address people reach it at |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web UI and git-over-HTTP on `:8080` and git-over-SSH on `:29418`.
Compose an exposure onto the HTTP port and route TCP `:29418` for SSH clones.

## Storage

The site directory `/var/gerrit` also holds the installed program
(`bin/gerrit.war`, `lib`), so a single volume over the whole site would hide it.
The four directories that must survive a restart get one PVC each — the
repositories, the Lucene index, the H2 databases and the configuration with its
host keys — and the regenerable ones (`cache`, `logs`, `tmp`, `data`, `static`,
`plugins`) are `emptyDir`, which keeps the root filesystem read-only.

The index is not among the regenerable ones: Gerrit does not rebuild an index it
cannot find, it refuses to start.

## Set the canonical URL

Gerrit writes `gerrit.canonicalWebUrl` on every start, from `CANONICAL_WEB_URL`
or, absent that, from the pod's hostname. A pod hostname changes with every pod,
and the links, clone commands and notification e-mails then point at a name
nobody can resolve. Pass `canonicalWebUrl` as soon as there is an address.

## Decide the authentication before you publish it

The batch initialisation leaves `auth.type` at `OpenID`, which on a
publicly-reachable address means anyone with an OpenID provider can sign in.
Put an authenticating proxy in front (`auth.type = HTTP`) or configure an
OAuth/LDAP provider in `etc/gerrit.config` before exposing it. Nothing in this
workload can decide it for you.

## First start is long

The entrypoint initialises the site, installs every bundled plugin and builds
the index before it serves a request. The startup probe carries that wait, so
the liveness delay stays short afterwards.

## Persistence

Repositories and H2 databases on ReadWriteOnce volumes, so this is **one replica,
recreated** (never rolled). Two servers writing one repository is not something
git sorts out afterwards.

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
metadata: { name: kurly, namespace: gerrit }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gerrit, namespace: gerrit }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gerrit, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gerrit }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gerrit, namespace: gerrit }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gerrit } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gerrit, namespace: gerrit }
spec:
  serviceAccountName: gerrit-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gerrit/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gerrit, importPath: github.com/metio/kurly/workloads/gerrit }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gerrit, namespace: gerrit }
spec:
  serviceAccountName: gerrit-deployer
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
        name: gerrit
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gerrit }
```

<!-- END generated: jaas-deploy -->
