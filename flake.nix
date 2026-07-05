# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The single source of the development toolchain: CI (verify.yml, release.yml)
# and local shells run every gate through this flake's devShell, so both use
# the exact tool versions pinned in flake.lock. Renovate keeps the lock fresh.
{
  description = "kurly development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Lets plain `nix-shell` reuse this flake's devShell via shell.nix.
    flake-compat.url = "github:edolstra/flake-compat";
  };

  outputs =
    { self, nixpkgs, ... }:
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
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            # Jsonnet toolchain: evaluator/formatter/linter mirror what jaas
            # embeds; jb vendors k8s-libsonnet the way the JOI images lay it out.
            go-jsonnet
            jsonnet-bundler

            # Manifest validation (hack/validate-examples.sh).
            kubeconform
            jq

            # The per-concern CI gates.
            reuse
            typos
            yamllint
            actionlint
            shellcheck # actionlint shells out to it for run: blocks
            markdownlint-cli2

            # Release plumbing: oras pushes the layer-per-stage OCI image,
            # cosign signs keyless, git-cliff renders the per-unit release
            # notes from conventional commits.
            oras
            cosign
            git-cliff
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
