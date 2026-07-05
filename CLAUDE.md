<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

kurly is a Jsonnet library of composable Kubernetes workload recipes (`http`, `worker`, `cron`, `daemon`) plus exposure recipes (`expose.*`), built on k8s-libsonnet. It publishes as the single-layer OCI image `ghcr.io/metio/kurly` (JOI-shaped: `FROM scratch`, jb-vendor-tree layout under `/github.com/metio/kurly/`), consumable by [jaas](https://github.com/metio/jaas) as a Flux `OCIRepository` source or an image-volume mount, and locally via `jb install`.

## Common commands

The toolchain and the dev-task commands are defined once in `flake.nix` and version-pinned by `flake.lock` (Renovate-maintained): CI runs every gate through the flake's devShell, so a gate that is green locally is green in CI by construction. Each multi-step gate is a `writeShellApplication` command (a `scripts/<name>.sh` file wrapped by nix — shellchecked at build, hermetic `runtimeInputs`), on `$PATH` inside `nix develop` and callable one-shot. There is no host task-runner (no `just`/Makefile wrapper) — the commands live in the shell they run in.

```shell
nix develop --command verify           # every gate, serially — the local pre-push check (what CI runs)
nix develop --command check-fmt        # jsonnetfmt --test across all sources
nix develop --command check-tests      # jb install + assertion suite + the requiresService negative check
nix develop --command check-examples   # render examples + workloads, validate with kubeconform
nix develop --command reuse lint       # the single-tool gates call the tool directly:
nix develop --command yamllint .
nix develop --command actionlint       # shellcheck rides in the devShell, so run: blocks are linted too
nix develop --command markdownlint-cli2 '**/*.md' '#vendor'
nix develop --command typos
```

Or drop into the shell — `nix develop` prints the command menu on entry, then run `verify` / `check-*` / any tool (`jsonnet`, `jb`, `kubeconform`, …) bare. Plain `nix-shell` works too (`shell.nix` reuses the flake via flake-compat, pinned through `flake.lock`).

On this host, `nix` is [nix-portable](https://github.com/DavHau/nix-portable) (`~/.local/bin/nix`, store in `~/.nix-portable` — user-level, no system install) and needs `NP_RUNTIME=bwrap` (exported in `~/.bashrc`; the auto-selected runtime cannot nest the build sandbox's mount namespace here). A system-level nix install is not possible on this Fedora Atomic host (the transient-root workaround broke boot). From a sandboxed shell, where nix-portable's user namespaces are blocked, resolve the same flake through the nix container image: `podman run --rm -v "$PWD:/work:z" -v metio-nix:/nix -w /work docker.io/nixos/nix:latest` with `NIX_CONFIG='experimental-features = nix-command flakes'`. **direnv is not usable here** — nix-portable's store is namespace-local, so an exported devShell env references `/nix` paths the host can't see; `nix develop` is the workflow. A contributor with a real nix install may add a local, gitignored `.envrc` (`use flake`) if they want direnv auto-loading.

jsonnet-lint is deliberately not part of the gate: it cannot resolve the vendored k8s-libsonnet's internal `doc-util` imports (jb `legacyImports: false`) and drowns real findings in vendor noise.

## Architecture

The library lives at the **repo root** (`main.libsonnet` + one file per workload kind) so the jb import path is `github.com/metio/kurly/main.libsonnet` — the same path the OCI image serves via jaas's vendor-tree search, keeping local and in-cluster imports identical. Deployable workloads live under **`workloads/<name>/`** (`stages.jsonnet` — a `kurly.stageLists` stage map — plus `migrations.jsonnet` — a migration ladder); each workload directory is an independently released unit (see CI below), so the library must stay at the root and workloads must stay in their directories.

- `k.libsonnet` — the single pin of the k8s-libsonnet API version (a directory like `1.35`); every module imports k8s-libsonnet through this file, so a version bump is one line.
- `base.libsonnet` — the shared core: a hidden `config::` object, computed `labels`/`container`/`podSecurity` fields that late-bind against it, the fluent `with*` modifiers, plus the `deployment` and `service` mixins the Deployment-backed kinds compose.
- `http|worker|cron|daemon.libsonnet` — one workload kind each: compose `base.core` (+ mixins) and add kind-specific manifests/modifiers.
- `expose.libsonnet` — exposure recipes composed onto a `kurly.http` app with `+`: `ingress` (Ingress API), and for the Gateway API `gateway`/`listenerSet` (attach an HTTPRoute to an existing parent) and `ownGateway`/`ownListenerSet` (generate the parent too). **Workload and exposure are deliberately two separate composable axes — do not fold routing back into a workload kind or add a mode toggle.** Every Gateway API recipe emits an HTTPRoute. Each recipe captures its `host` argument lexically (not via `config`), so several exposures compose with independent hosts. A shared `requiresService` object-level assert fails composition onto Service-less kinds. The Gateway API objects are plain manifests (no gateway-api-libsonnet) to keep consumers' render-time dependency closure at k8s-libsonnet alone; ListenerSet is GA (`gateway.networking.k8s.io/v1`, Gateway API ≥ 1.5), and the shared Gateway a ListenerSet attaches to must opt in via `spec.allowedListeners`.
- `security.libsonnet` — the Pod Security Standards profiles (`restricted`/`baseline`/`privileged`) as composable mixins, same axis pattern as `expose`. Each profile sets **every** security knob in `config`, so the last profile composed wins and the single-knob hatches fine-tune after it. `baseline` relaxes only what `restricted` requires beyond baseline and keeps kurly's extra hardening (read-only rootfs, user namespaces); `privileged` emits no security fields at all. The ServiceAccount-token automount rule is deliberately outside every profile (it is SA hygiene, not PSS).
- `migrations.libsonnet` — `migration(name, to, from=null, stage=null, actions=[])` builds one entry of a stageset-controller migration ladder (the serialized `[]Migration` behind `spec.migrationsSourceRef`); a ladder is a plain Jsonnet array of them. Optional fields and empty action lists are pruned. Actions are stageset-controller `Action` objects passed through **verbatim** — kurly deliberately does not model their schema (it would drift against stageset's API).
- `main.libsonnet` — the entry point: exposes the kinds, `expose`, `security`, `migrations`, `list(app)` (wraps an app's manifests in a `kind: List`), and the stage helpers: `stages(app, overlays)` maps stage name → composed app (still open for further composition), `stageLists(app, overlays)` maps stage name → `kind: List` — the shape the workload artifact pipeline consumes.

**The fluent pattern:** `new(name, image)` returns an object whose hidden `config::` holds all knobs, whose hidden `with*(…)::` methods return `self + { config+:: … }`, and whose *visible* fields are the manifests, computed from `self.config` — so modifiers late-bind regardless of call order, and `std.objectValues(app)` is exactly the manifest set. Two traps:

- Inside a field whose value is a **nested object literal**, `self` binds to that literal, not the app — `base.core` captures `local this = self` for those cases (e.g. `selectorLabels`), and the expose recipes capture `local app = self` for the same reason.
- A mixin that **adds a manifest** must compute it from `self.config`/captured args, never from another method on `self` that it is simultaneously overriding (self-recursion).

**Selector stability:** `selectorLabels` (plus the `name` label k8s-libsonnet's constructors force) feed immutable `matchLabels`; user labels from `withLabels` go to metadata + pod template only. Do not let user labels reach a selector.

**Security defaults:** every kind ships the Pod Security Standards `restricted` profile — every setting is a `config::` knob (runAsNonRoot, seccompProfile, allowPrivilegeEscalation, dropAllCapabilities, readOnlyRootFilesystem, hostUsers) rendered pod-level via `base.core`'s `podSecurity::` fragment and container-level in `container::`. A relaxed knob **omits** its field from the manifest rather than writing the Kubernetes default explicitly — so `security.privileged` output carries no security stanzas at all. Knobs relax two ways: the single-knob hatches (`withRootUser`, `withWritableRootFilesystem`, `withHostUsers`) or the `kurly.security.*` profile mixins (which set all knobs — hatches must chain *after* a profile). `automountServiceAccountToken` (only with an explicit ServiceAccount) is outside both. New workload kinds must merge `podSecurity` into their pod template spec and inherit `container::`; keep the default posture fully `restricted`.

## Dependency policy

`jsonnetfile.json` pins k8s-libsonnet to `main`, and `vendor/` + the lock file are **gitignored**: the JOI k8s-libsonnet image tracks upstream HEAD daily, so CI vendoring HEAD tests exactly what clusters run — an upstream break in CI is a wanted signal. Do not commit a lock file or pin a SHA. k8s-libsonnet is **not bundled** into the OCI image; jaas supplies it at render time as its own JsonnetLibrary.

## Tests

`tests/kurly_test.jsonnet` is an assertion suite: every field is a `std.assertEqual` (raises on mismatch), and CI additionally checks all values are `true` via jq. The `requiresService` assert is covered by a negative check in the CI test job (a worker + exposure composition must fail to evaluate) — jsonnet has no try/catch, so error paths cannot live in the assertion suite. The examples double as end-to-end fixtures: `hack/validate-examples.sh` renders each one, splits the `List` items, and validates every manifest with kubeconform `-strict` — core kinds against the upstream Kubernetes schemas, Gateway API kinds against the community CRD schema catalog (`-ignore-missing-schemas` covers kinds absent from both, e.g. XListenerSet; watch the summary's skipped count).

## Workload artifact contract

A staged workload publishes as **one OCI image with one layer per rollout stage** plus one for the migration ladder — one version, one signature, one changelog entry across every stage. Layer media types are the contract consumers select on (`OCIRepository.spec.layerSelector.mediaType`):

- stage layer: `application/vnd.metio.stage.<stage>.tar+gzip` (contents: one JSON manifest file per List item)
- migrations layer: `application/vnd.metio.migrations.tar+gzip` (contents: `migrations.yaml`, the serialized `[]Migration` — JSON on the wire, which every YAML loader accepts)

`hack/build-workload-artifact.sh <stages.jsonnet> <migrations.jsonnet> <outdir>` renders and packs the layer set and emits `layers.txt` (`file:mediaType` pairs, stages sorted, migrations last) for `oras push`. Tarballs are **deterministic** (sorted entries, zero timestamps, numeric owner 0:0, `gzip -n`) so unchanged sources yield identical layer digests. Consumers must always set `layerSelector` — Flux extracts the first layer when it is omitted. This is the deliberate opposite of the library image, which stays **single-layer** so it works as an image-volume mount and a selector-less OCIRepository source.

## CI

`verify.yml` is the PR gate (fmt, test, examples, reuse, yaml, github-actions, markdown, typos, dco), ending in the single `Verify` aggregate job — the only check to mark required in branch protection. Every tool job is checkout → the repo-local composite `.github/actions/nix-devshell` → `nix develop --command <gate>`: the composite installs Nix (`DeterminateSystems/nix-installer-action`) and caches the `/nix` store through the GitHub Actions cache (`nix-community/cache-nix-action`, keyed on `hashFiles(flake.nix, flake.lock)` with a prefix-fallback restore), so the devShell closure is downloaded only when the flake pin changes — every other run restores it in seconds. The tools come from the flake's devShell, pinned by `flake.lock`, never from marketplace actions or `@latest` installs — so CI and local shells cannot disagree on versions. The `dco` job is the one exception (pure git, no tools). `release.yml` does **multi-unit releases from one repository, modeled on metio/helm-charts**: the releasable units are the library (root `*.libsonnet` + `Containerfile`) and every directory under `workloads/`. A `discover` job classifies this push's diff per unit (dispatch force-releases one unit or, with empty input, everything — also the recovery path for a failed run, since change detection covers only the push's own range); all units released in one run share a single `metio/ci/calver` version, but each gets its own tag (`library-<version>`, `<workload>-<version>`), its own GitHub Release, and its own notes via `metio/ci/release-notes` scoped by **`include-paths` and `tag-pattern`** to that unit's files and tag lineage — one unit's commits never leak into another's changelog. The workload matrix runs with `fail-fast: false` so one unit's failure never blocks another's release. The `library` job asserts **exactly one layer** and publishes via `metio/ci/container-release`; each `workload` job packs the layer-per-stage image (built by `hack/build-workload-artifact.sh`, pushed with `oras`, signed with `cosign`, both from the flake). A workload directory must never be named `library` (tag-prefix collision; the discover job fails on it). Library changes deliberately do **not** re-release workloads — a workload picks up library changes with its own next release or a forced dispatch, mirroring helm-charts' common-chart handling. Renovate keeps `flake.lock` fresh (the repo-local `renovate.json` enables the `nix` manager + lock-file maintenance on top of the org preset).
