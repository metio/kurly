# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The single source of the development toolchain and the dev-task commands: CI
# (verify.yml, release.yml) and local shells run every gate through this flake's
# devShell, so both use the exact tool versions pinned in flake.lock. The shared
# lint gate and the org-wide nixpkgs pin come from the metio/ci flake; Renovate
# keeps the lock fresh.
#
# Gates are `writeShellApplication` commands (plain scripts/ files wrapped by
# nix): shellchecked at build, with hermetic runtimeInputs, on PATH inside
# `nix develop` and callable as `nix develop --command <name>`. There is no host
# task-runner layer — the commands live in the shell they run in.
{
  description = "kurly development environment";

  inputs = {
    devshell.url = "github:metio/nix-devshell";
    nixpkgs.follows = "devshell/nixpkgs";
    # Lets plain `nix-shell` reuse this flake's devShell via shell.nix.
    flake-compat.follows = "devshell/flake-compat";
  };

  outputs =
    {
      self,
      nixpkgs,
      devshell,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          # kurly's own toolchain: the Jsonnet renderer/formatter/bundler,
          # manifest validation, and the release plumbing.
          kurlyTools = with pkgs; [
            go-jsonnet
            jsonnet-bundler
            kubeconform
            jq
            oras
            cosign
          ];

          # The documentation site: Hugo builds the static site (the metio theme
          # is a git submodule under docs/themes/), and the assembler page reads
          # catalog/catalog.json copied into docs/data/ by gen-docs-data.
          docsTools = with pkgs; [
            hugo
          ];

          # Kubernetes static analysis, weighted toward custom policy: conftest
          # runs kurly's own invariants as Rego over the RENDERED JSON (the layer
          # jsonnet emits) — precise, no ignore-list upkeep — backed by two
          # small, fast, no-config tools that earn their cost: pluto (removed /
          # deprecated API detection) and kubesec (a security risk score).
          # kubeconform (schema) rides in kurlyTools via check-examples.
          securityTools = with pkgs; [
            conftest
            pluto
            kubesec
          ];

          # The kind smoke test's toolchain: a throwaway cluster and kubectl.
          # Applies kurly's rendered output and waits for it to become Ready —
          # proving the manifests run, not just that they validate.
          smokeTools = with pkgs; [
            kind
            kubectl
          ];

          # Multi-step gate commands. Each is a plain scripts/<name>.sh that nix
          # wraps with `set -euo pipefail`, shellchecks at build, and runs with
          # its own hermetic runtimeInputs — so a macOS contributor gets nix's
          # tools, not the host's BSD ones.
          check-fmt = pkgs.writeShellApplication {
            name = "check-fmt";
            runtimeInputs = [ pkgs.go-jsonnet ];
            text = builtins.readFile ./scripts/check-fmt.sh;
          };
          check-tests = pkgs.writeShellApplication {
            name = "check-tests";
            runtimeInputs = with pkgs; [
              go-jsonnet
              jsonnet-bundler
              jq
            ];
            text = builtins.readFile ./scripts/check-tests.sh;
          };
          check-catalog = pkgs.writeShellApplication {
            name = "check-catalog";
            runtimeInputs = with pkgs; [
              go-jsonnet
              jsonnet-bundler
              diffutils
              coreutils
            ];
            text = builtins.readFile ./scripts/check-catalog.sh;
          };
          check-examples = pkgs.writeShellApplication {
            name = "check-examples";
            runtimeInputs = with pkgs; [
              go-jsonnet
              jsonnet-bundler
              jq
              kubeconform
              coreutils
            ];
            text = builtins.readFile ./scripts/check-examples.sh;
          };
          # The catalog-driven coverage battery: render every feature/recipe/
          # profile/kind composition generated from the catalog and validate each
          # manifest with kubeconform.
          check-coverage = pkgs.writeShellApplication {
            name = "check-coverage";
            runtimeInputs = with pkgs; [
              go-jsonnet
              jsonnet-bundler
              jq
              kubeconform
              coreutils
            ];
            text = builtins.readFile ./scripts/check-coverage.sh;
          };
          check-security = pkgs.writeShellApplication {
            name = "check-security";
            runtimeInputs = with pkgs; [
              go-jsonnet
              jsonnet-bundler
              jq
              coreutils
            ]
            ++ securityTools;
            text = builtins.readFile ./scripts/check-security.sh;
          };
          # Stages the generated data the docs site reads into docs/data/
          # (gitignored) — currently the assembler catalog. Run before `hugo`;
          # the docs workflow runs it too, so the published site is always built
          # from the committed catalog rather than a stale copy.
          gen-docs-data = pkgs.writeShellApplication {
            name = "gen-docs-data";
            runtimeInputs = with pkgs; [
              coreutils
              curl
              cacert
            ];
            text = builtins.readFile ./scripts/gen-docs-data.sh;
          };
          # Applies kurly's output to a running cluster and waits for Ready. Not
          # part of `verify` (it needs a cluster); the kind-smoke workflow owns
          # creating the throwaway kind cluster around it.
          kind-smoke = pkgs.writeShellApplication {
            name = "kind-smoke";
            runtimeInputs = with pkgs; [
              go-jsonnet
              jsonnet-bundler
              jq
              kubectl
              coreutils
              cacert
            ];
            text = builtins.readFile ./scripts/kind-smoke.sh;
          };
          # Runs every gate locally (the serial equivalent of CI's parallel
          # jobs); its runtimeInputs are the other commands plus the shared lint
          # gate from the metio/ci flake.
          verify = pkgs.writeShellApplication {
            name = "verify";
            runtimeInputs = [
              check-fmt
              check-catalog
              check-tests
              check-examples
              check-coverage
              check-security
            ]
            ++ devshell.lib.lintTools pkgs;
            text = builtins.readFile ./scripts/verify.sh;
          };
          commands = [
            check-fmt
            check-catalog
            check-tests
            check-examples
            check-coverage
            check-security
            gen-docs-data
            kind-smoke
            verify
          ];
        in
        {
          default = devshell.lib.mkDevShell {
            inherit pkgs;
            packages = kurlyTools ++ securityTools ++ smokeTools ++ docsTools ++ commands;
            menu = ''
              echo "kurly commands (also: nix develop --command <name>):"
              echo "  check-fmt        jsonnetfmt --test across all sources"
              echo "  check-catalog    regenerate catalog/catalog.json, fail if stale"
              echo "  check-tests      assertion suite + the requiresService negative check"
              echo "  check-examples   render examples + workloads, validate with kubeconform"
              echo "  check-coverage   render every catalog composition, validate with kubeconform"
              echo "  check-security   conftest Rego policy + pluto (deprecated APIs) + kubesec"
              echo "  gen-docs-data    stage catalog.json into docs/data/ for the site"
              echo "  kind-smoke       apply kurly's output to a cluster, wait for Ready"
              echo "  verify           run every gate locally (what CI runs)"
            '';
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
