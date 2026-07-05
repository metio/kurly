<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

kurly is a Jsonnet library of composable Kubernetes workload recipes (`http`, `worker`, `cron`, `daemon`) plus exposure recipes (`expose.*`), built on k8s-libsonnet. It publishes as the single-layer OCI image `ghcr.io/metio/kurly` (JOI-shaped: `FROM scratch`, jb-vendor-tree layout under `/github.com/metio/kurly/`), consumable by [jaas](https://github.com/metio/jaas) as a Flux `OCIRepository` source or an image-volume mount, and locally via `jb install`.

## Common commands

The toolchain is defined once in `flake.nix` and version-pinned by `flake.lock` (Renovate-maintained): CI runs every gate through the flake's devShell, so a gate that is green locally is green in CI by construction. With nix installed, enter the shell via `nix develop` (plain `nix-shell` works too — `shell.nix` reuses the flake via flake-compat, pinned through `flake.lock`):

```shell
nix develop --command jb install                                    # vendor k8s-libsonnet (needed once, gitignored)
nix develop --command jsonnet -J vendor tests/kurly_test.jsonnet    # run the assertion suite
nix develop --command jsonnetfmt --test ./*.libsonnet examples/*.jsonnet tests/*.jsonnet  # format gate (-i to fix)
nix develop --command ./hack/validate-examples.sh                   # render examples + kubeconform
nix develop --command yamllint .                                    # CI yaml gate
nix develop --command actionlint                                    # CI workflow gate (shellcheck comes from the shell too)
nix develop --command typos                                         # CI spelling gate
nix develop --command reuse lint                                    # CI REUSE gate
nix develop --command markdownlint-cli2 '**/*.md' '#vendor'         # CI markdown gate
```

On a host without nix, the same commands run inside the containerized dev shell driven by `dev/Containerfile` (`ilo bash -c '…'`), or through the nix container image (`podman run --rm -v "$PWD:/work:z" -v kurly-nix:/nix -w /work docker.io/nixos/nix:latest`, with `NIX_CONFIG='experimental-features = nix-command flakes'`). The ilo shell installs tools at `@latest` and can drift ahead of `flake.lock` — when versions disagree, the flake is authoritative because it is what CI runs.

jsonnet-lint is deliberately not part of the gate: it cannot resolve the vendored k8s-libsonnet's internal `doc-util` imports (jb `legacyImports: false`) and drowns real findings in vendor noise.

## Architecture

The library lives at the **repo root** (`main.libsonnet` + one file per workload kind) so the jb import path is `github.com/metio/kurly/main.libsonnet` — the same path the OCI image serves via jaas's vendor-tree search, keeping local and in-cluster imports identical.

- `k.libsonnet` — the single pin of the k8s-libsonnet API version (a directory like `1.35`); every module imports k8s-libsonnet through this file, so a version bump is one line.
- `base.libsonnet` — the shared core: a hidden `config::` object, computed `labels`/`container`/`podSecurity` fields that late-bind against it, the fluent `with*` modifiers, plus the `deployment` and `service` mixins the Deployment-backed kinds compose.
- `http|worker|cron|daemon.libsonnet` — one workload kind each: compose `base.core` (+ mixins) and add kind-specific manifests/modifiers.
- `expose.libsonnet` — exposure recipes composed onto a `kurly.http` app with `+`: `ingress` (Ingress API), and for the Gateway API `gateway`/`listenerSet` (attach an HTTPRoute to an existing parent) and `ownGateway`/`ownListenerSet` (generate the parent too). **Workload and exposure are deliberately two separate composable axes — do not fold routing back into a workload kind or add a mode toggle.** Every Gateway API recipe emits an HTTPRoute. Each recipe captures its `host` argument lexically (not via `config`), so several exposures compose with independent hosts. A shared `requiresService` object-level assert fails composition onto Service-less kinds. The Gateway API objects are plain manifests (no gateway-api-libsonnet) to keep consumers' render-time dependency closure at k8s-libsonnet alone; ListenerSet is GA (`gateway.networking.k8s.io/v1`, Gateway API ≥ 1.5), and the shared Gateway a ListenerSet attaches to must opt in via `spec.allowedListeners`.
- `security.libsonnet` — the Pod Security Standards profiles (`restricted`/`baseline`/`privileged`) as composable mixins, same axis pattern as `expose`. Each profile sets **every** security knob in `config`, so the last profile composed wins and the single-knob hatches fine-tune after it. `baseline` relaxes only what `restricted` requires beyond baseline and keeps kurly's extra hardening (read-only rootfs, user namespaces); `privileged` emits no security fields at all. The ServiceAccount-token automount rule is deliberately outside every profile (it is SA hygiene, not PSS).
- `main.libsonnet` — the entry point: exposes the kinds, `expose`, `security`, and `list(app)` (wraps an app's manifests in a `kind: List`).

**The fluent pattern:** `new(name, image)` returns an object whose hidden `config::` holds all knobs, whose hidden `with*(…)::` methods return `self + { config+:: … }`, and whose *visible* fields are the manifests, computed from `self.config` — so modifiers late-bind regardless of call order, and `std.objectValues(app)` is exactly the manifest set. Two traps:

- Inside a field whose value is a **nested object literal**, `self` binds to that literal, not the app — `base.core` captures `local this = self` for those cases (e.g. `selectorLabels`), and the expose recipes capture `local app = self` for the same reason.
- A mixin that **adds a manifest** must compute it from `self.config`/captured args, never from another method on `self` that it is simultaneously overriding (self-recursion).

**Selector stability:** `selectorLabels` (plus the `name` label k8s-libsonnet's constructors force) feed immutable `matchLabels`; user labels from `withLabels` go to metadata + pod template only. Do not let user labels reach a selector.

**Security defaults:** every kind ships the Pod Security Standards `restricted` profile — every setting is a `config::` knob (runAsNonRoot, seccompProfile, allowPrivilegeEscalation, dropAllCapabilities, readOnlyRootFilesystem, hostUsers) rendered pod-level via `base.core`'s `podSecurity::` fragment and container-level in `container::`. A relaxed knob **omits** its field from the manifest rather than writing the Kubernetes default explicitly — so `security.privileged` output carries no security stanzas at all. Knobs relax two ways: the single-knob hatches (`withRootUser`, `withWritableRootFilesystem`, `withHostUsers`) or the `kurly.security.*` profile mixins (which set all knobs — hatches must chain *after* a profile). `automountServiceAccountToken` (only with an explicit ServiceAccount) is outside both. New workload kinds must merge `podSecurity` into their pod template spec and inherit `container::`; keep the default posture fully `restricted`.

## Dependency policy

`jsonnetfile.json` pins k8s-libsonnet to `main`, and `vendor/` + the lock file are **gitignored**: the JOI k8s-libsonnet image tracks upstream HEAD daily, so CI vendoring HEAD tests exactly what clusters run — an upstream break in CI is a wanted signal. Do not commit a lock file or pin a SHA. k8s-libsonnet is **not bundled** into the OCI image; jaas supplies it at render time as its own JsonnetLibrary.

## Tests

`tests/kurly_test.jsonnet` is an assertion suite: every field is a `std.assertEqual` (raises on mismatch), and CI additionally checks all values are `true` via jq. The `requiresService` assert is covered by a negative check in the CI test job (a worker + exposure composition must fail to evaluate) — jsonnet has no try/catch, so error paths cannot live in the assertion suite. The examples double as end-to-end fixtures: `hack/validate-examples.sh` renders each one, splits the `List` items, and validates every manifest with kubeconform `-strict` — core kinds against the upstream Kubernetes schemas, Gateway API kinds against the community CRD schema catalog (`-ignore-missing-schemas` covers kinds absent from both, e.g. XListenerSet; watch the summary's skipped count).

## CI

`verify.yml` is the PR gate (fmt, test, examples, reuse, yaml, github-actions, markdown, typos, dco), ending in the single `Verify` aggregate job — the only check to mark required in branch protection. Every tool job is checkout → the repo-local composite `.github/actions/nix-devshell` → `nix develop --command <gate>`: the composite installs Nix (`DeterminateSystems/nix-installer-action`) and caches the `/nix` store through the GitHub Actions cache (`nix-community/cache-nix-action`, keyed on `hashFiles(flake.nix, flake.lock)` with a prefix-fallback restore), so the devShell closure is downloaded only when the flake pin changes — every other run restores it in seconds. The tools come from the flake's devShell, pinned by `flake.lock`, never from marketplace actions or `@latest` installs — so CI and local shells cannot disagree on versions. The `dco` job is the one exception (pure git, no tools). `release.yml` runs on pushes to `main` touching the library: its validate job re-runs the tests through the same devShell, then builds the image, asserts **exactly one layer** (the contract that makes the image dual-consumable), pushes `:latest` + a dated calver tag over the six standard metio arches, and cosign-signs by digest. Renovate keeps `flake.lock` fresh (the repo-local `renovate.json` enables the `nix` manager + lock-file maintenance on top of the org preset).
