<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

kurly is a Jsonnet library of composable Kubernetes workload recipes (`web`, `api`, `worker`, `cron`, `daemon`), built on k8s-libsonnet. It publishes as the single-layer OCI image `ghcr.io/metio/kurly` (JOI-shaped: `FROM scratch`, jb-vendor-tree layout under `/github.com/metio/kurly/`), consumable by [jaas](https://github.com/metio/jaas) as a Flux `OCIRepository` source or an image-volume mount, and locally via `jb install`.

## Common commands

This host has no toolchain installed; commands run inside the containerized dev shell driven by `dev/Containerfile` (a `.ilo.rc` at the repo root supplies the args):

```shell
ilo bash -c 'jb install'                                    # vendor k8s-libsonnet (needed once, gitignored)
ilo bash -c 'jsonnet -J vendor tests/kurly_test.jsonnet'    # run the assertion suite
ilo bash -c 'jsonnetfmt --test *.libsonnet examples/*.jsonnet tests/*.jsonnet'  # format gate (-i to fix)
ilo bash -c './hack/validate-examples.sh'                   # render examples + kubeconform
ilo bash -c 'yamllint .'                                    # CI yaml gate
ilo bash -c 'actionlint'                                    # CI workflow gate
ilo bash -c 'typos'                                         # CI spelling gate
ilo bash -c 'reuse lint'                                    # CI REUSE gate
```

jsonnet-lint is deliberately not part of the gate: it cannot resolve the vendored k8s-libsonnet's internal `doc-util` imports (jb `legacyImports: false`) and drowns real findings in vendor noise.

## Architecture

The library lives at the **repo root** (`main.libsonnet` + one file per workload kind) so the jb import path is `github.com/metio/kurly/main.libsonnet` — the same path the OCI image serves via jaas's vendor-tree search, keeping local and in-cluster imports identical.

- `k.libsonnet` — the single pin of the k8s-libsonnet API version (a directory like `1.35`); every module imports k8s-libsonnet through this file, so a version bump is one line.
- `base.libsonnet` — the shared core: a hidden `config::` object, computed `labels`/`container`/`podSecurity` fields that late-bind against it, the fluent `with*` modifiers, plus the `deployment` and `service` mixins the Deployment-backed kinds compose.
- `web|api|worker|cron|daemon.libsonnet` — one workload kind each: compose `base.core` (+ mixins) and add kind-specific manifests/modifiers.
- `main.libsonnet` — the entry point: exposes the kinds plus `list(app)` (wraps an app's manifests in a `kind: List`).

**The fluent pattern:** `new(name, image)` returns an object whose hidden `config::` holds all knobs, whose hidden `with*(…)::` methods return `self + { config+:: … }`, and whose *visible* fields are the manifests, computed from `self.config` — so modifiers late-bind regardless of call order, and `std.objectValues(app)` is exactly the manifest set. Two traps:

- Inside a field whose value is a **nested object literal**, `self` binds to that literal, not the app — `base.core` captures `local this = self` for those cases (e.g. `selectorLabels`).
- A modifier that **adds a manifest** (e.g. `withHost` adding `ingress`) must compute it from `self.config`, never from another method on `self` that it is simultaneously overriding (self-recursion).

**Selector stability:** `selectorLabels` (plus the `name` label k8s-libsonnet's constructors force) feed immutable `matchLabels`; user labels from `withLabels` go to metadata + pod template only. Do not let user labels reach a selector.

**Security defaults:** every kind ships the Pod Security Standards `restricted` profile — pod-level via `base.core`'s `podSecurity::` fragment (runAsNonRoot, seccomp `RuntimeDefault`, `hostUsers: false`, `automountServiceAccountToken` only with an explicit ServiceAccount), container-level in `container::` (no privilege escalation, drop ALL capabilities, read-only root filesystem). Each escape hatch (`withRootUser`, `withWritableRootFilesystem`, `withHostUsers`) downgrades exactly one default. New workload kinds must merge `podSecurity` into their pod template spec and inherit `container::`.

## Dependency policy

`jsonnetfile.json` pins k8s-libsonnet to `main`, and `vendor/` + the lock file are **gitignored**: the JOI k8s-libsonnet image tracks upstream HEAD daily, so CI vendoring HEAD tests exactly what clusters run — an upstream break in CI is a wanted signal. Do not commit a lock file or pin a SHA. k8s-libsonnet is **not bundled** into the OCI image; jaas supplies it at render time as its own JsonnetLibrary.

## Tests

`tests/kurly_test.jsonnet` is an assertion suite: every field is a `std.assertEqual` (raises on mismatch), and CI additionally checks all values are `true` via jq. The examples double as end-to-end fixtures: `hack/validate-examples.sh` renders each one, splits the `List` items, and validates every manifest with kubeconform `-strict` against the upstream Kubernetes schemas.

## CI

`verify.yml` is the PR gate (fmt, test, examples, reuse, yaml, github-actions, markdown, typos, dco), ending in the single `Verify` aggregate job — the only check to mark required in branch protection. `release.yml` runs on pushes to `main` touching the library: it re-runs the tests, builds the image, asserts **exactly one layer** (the contract that makes the image dual-consumable), pushes `:latest` + a dated calver tag over the six standard metio arches, and cosign-signs by digest. CI installs Jsonnet tools fresh via `go run`/`go install @latest`; the dev shell pre-installs the same tools so local and CI agree.
