<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# multi-scrobbler

[multi-scrobbler](https://github.com/FoxxMD/multi-scrobbler) — it watches what you
are listening to across many sources (Spotify, Plex, Jellyfin, YouTube Music, a
desktop player) and forwards each play to the scrobbling services that keep your
history, such as Last.fm, ListenBrainz or Maloja. A plain composable `kurly.http`
workload; its configuration, credentials and play database live on a
PersistentVolume at `/config`.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ms = import 'github.com/metio/kurly/workloads/multi-scrobbler/server.libsonnet';

kurly.list(ms(baseUrl='https://scrobble.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `multi-scrobbler` | |
| `image` | `foxxmd/multi-scrobbler:0.15.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/config` |
| `baseUrl` | none | the public URL OAuth returns to |
| `puid` / `pgid` | `1000` / `1000` | owns the files on the volume |
| `timezone` | `UTC` | `TZ` |
| `env` / `resources` / `labels` / `annotations` | | |

## `baseUrl` is the one value only you know

Every source that authenticates by OAuth builds its redirect URI from `BASE_URL`.
Leave it unset and the browser is sent back to an address that is not this
instance, so the authorisation never completes and the source stays disconnected.
Set it to the public URL your exposure actually serves. It has no default because
a placeholder would be wrong everywhere it is really deployed.

Configuration itself is either environment variables or JSON files under `/config`
— the volume also holds the credentials each source hands back and the database of
plays waiting to be forwarded, which is why it is worth keeping.

## Less hardened, deliberately

The image is built on the LinuxServer.io base, whose s6-overlay init starts as
root and drops to the `PUID`/`PGID` user. So this runs as root and is granted back
by name only the capabilities that hand-off needs (`CHOWN`, `DAC_OVERRIDE`,
`FOWNER`, `SETGID`, `SETUID`); everything else stays dropped, and the rest of the
hardening is untouched — seccomp, no privilege escalation, a read-only root
filesystem with scratch volumes at `/run` and `/tmp`.

## Probes read the port, not the health endpoint

The dashboard's health endpoint reports the state of the *configured* sources. A
fresh instance with nothing configured yet, or one whose Last.fm token has just
expired, answers unhealthy — and a liveness probe reading that would restart the
pod forever over something no restart fixes. The probes here open the port
instead.

## Persistence

One SQLite database and one credentials directory on a ReadWriteOnce volume, so
this is **one replica, recreated** (never rolled).

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
metadata: { name: kurly, namespace: multi-scrobbler }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-multi-scrobbler, namespace: multi-scrobbler }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/multi-scrobbler, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: multi-scrobbler }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-multi-scrobbler, namespace: multi-scrobbler }
spec: { sourceRef: { kind: OCIRepository, name: kurly-multi-scrobbler } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: multi-scrobbler, namespace: multi-scrobbler }
spec:
  serviceAccountName: multi-scrobbler-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/multi-scrobbler/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-multi-scrobbler, importPath: github.com/metio/kurly/workloads/multi-scrobbler }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: multi-scrobbler, namespace: multi-scrobbler }
spec:
  serviceAccountName: multi-scrobbler-deployer
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
        name: multi-scrobbler
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: multi-scrobbler }
```

<!-- END generated: jaas-deploy -->
