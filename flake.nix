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
    ci.url = "github:metio/ci";
    nixpkgs.follows = "ci/nixpkgs";
    # Lets plain `nix-shell` reuse this flake's devShell via shell.nix.
    flake-compat.follows = "ci/flake-compat";
  };

  outputs =
    {
      self,
      nixpkgs,
      ci,
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
          # Runs every gate locally (the serial equivalent of CI's parallel
          # jobs); its runtimeInputs are the other commands plus the shared lint
          # gate from the metio/ci flake.
          verify = pkgs.writeShellApplication {
            name = "verify";
            runtimeInputs = [
              check-fmt
              check-tests
              check-examples
            ]
            ++ ci.lib.lintTools pkgs;
            text = builtins.readFile ./scripts/verify.sh;
          };
          commands = [
            check-fmt
            check-tests
            check-examples
            verify
          ];
        in
        {
          default = ci.lib.mkDevShell {
            inherit pkgs;
            packages = kurlyTools ++ commands;
            menu = ''
              echo "kurly commands (also: nix develop --command <name>):"
              echo "  check-fmt        jsonnetfmt --test across all sources"
              echo "  check-tests      assertion suite + the requiresService negative check"
              echo "  check-examples   render examples + workloads, validate with kubeconform"
              echo "  verify           run every gate locally (what CI runs)"
            '';
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
