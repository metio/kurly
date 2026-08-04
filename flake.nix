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
            # The docs site ships the assembler, a browser component whose output
            # visitors paste into their clusters; check-assembler drives it.
            nodejs-slim
          ];

          # Kubernetes static analysis, weighted toward custom policy: conftest
          # runs kurly's own invariants as Rego over the RENDERED JSON (the layer
          # jsonnet emits) — precise, no ignore-list upkeep — backed by two
          # small, fast, no-config tools that earn their cost: pluto (removed /
          # deprecated API detection) and kubesec (a security risk score).
          # kubeconform (schema) rides in kurlyTools via check-examples.
          # Renovate is in the shell only for its config validator: an invalid
          # renovate.json stops every dependency update and announces it in an
          # issue rather than in CI, so it is checked like any other config.
          renovateTools = [ pkgs.renovate ];

          securityTools = with pkgs; [
            conftest
            pluto
            kubesec
          ];

          # The e2e toolchain: a throwaway kind cluster and kubectl, used by the
          # per-workload e2e scenarios (hack/smoke/) via nix develop.
          # Applies kurly's rendered output and waits for it to become Ready —
          # proving the manifests run, not just that they validate.
          smokeTools = with pkgs; [
            kind
            kubectl
            kubernetes-helm
            curl
            minikube
            # Linkerd's helm install wants an mTLS trust anchor and issuer up
            # front — the `linkerd` CLI mints them, helm does not — so the mesh
            # scenario builds them here, from the toolchain rather than from
            # whatever openssl the host happens to carry.
            step-cli
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
          # Drives the docs site's assembler the way the page does and checks that
          # what it hands a visitor actually parses — as Jsonnet, and as YAML.
          check-assembler = pkgs.writeShellApplication {
            name = "check-assembler";
            runtimeInputs = with pkgs; [
              nodejs-slim
              go-jsonnet
              yq-go
              coreutils
            ];
            text = builtins.readFile ./scripts/check-assembler.sh;
          };
          check-tests = pkgs.writeShellApplication {
            name = "check-tests";
            runtimeInputs = with pkgs; [
              go-jsonnet
              jsonnet-bundler
              jq
              gnugrep
              git
              gnused
              coreutils
            ];
            text = builtins.readFile ./scripts/check-tests.sh;
          };
          # Derives each workload's maturity tier from the repository's own
          # signals (smoke scenarios, test assertions) into
          # catalog/maturity.gen.libsonnet, which catalog.jsonnet imports.
          gen-maturity = pkgs.writeShellApplication {
            name = "gen-maturity";
            runtimeInputs = with pkgs; [
              findutils
              gnugrep
              git
              gnused
              coreutils
            ];
            text = builtins.readFile ./scripts/gen-maturity.sh;
          };
          # Derives each stage's image architectures from the registry manifest
          # lists into catalog/architectures.gen.libsonnet. Hits the network, so
          # it is run on demand / on a schedule, not in the per-PR gate.
          gen-architectures = pkgs.writeShellApplication {
            name = "gen-architectures";
            # inspect_one runs under xargs, where shellcheck cannot see the call.
            excludeShellChecks = [ "SC2329" ];
            runtimeInputs = with pkgs; [
              skopeo
              jq
              git
              gnused
              go-jsonnet
              coreutils
            ];
            text = builtins.readFile ./scripts/gen-architectures.sh;
          };
          # Derives whether each stage's image carries a verifiable sigstore
          # signature, and who signed it, into catalog/signatures.gen.libsonnet.
          # Hits the network twice per stage, so it is run on demand / on a
          # schedule, not in the per-PR gate.
          gen-signatures = pkgs.writeShellApplication {
            name = "gen-signatures";
            # inspect_one and its helpers run under xargs, where shellcheck
            # cannot see the call.
            excludeShellChecks = [ "SC2329" ];
            runtimeInputs = with pkgs; [
              cosign
              openssl
              jq
              git
              gnugrep
              gnused
              go-jsonnet
              coreutils
            ];
            text = builtins.readFile ./scripts/gen-signatures.sh;
          };
          # Asks a kind cluster's API server which bollwerk policies each stage
          # violates, into catalog/bsi.gen.libsonnet. Needs a cluster (only an API
          # server evaluates the policies' CEL faithfully), so it runs in the e2e
          # workflow rather than the per-PR gate.
          gen-bsi = pkgs.writeShellApplication {
            name = "gen-bsi";
            # The cleanup function runs from a trap, which shellcheck cannot see.
            excludeShellChecks = [ "SC2329" ];
            runtimeInputs = with pkgs; [
              go-jsonnet
              jsonnet-bundler
              kubectl
              jq
              gnugrep
              gawk
              coreutils
            ];
            text = builtins.readFile ./scripts/gen-bsi.sh;
          };
          # Writes the artifacts a catalogue describes into it, at release time.
          # Release-only: the artifacts it names do not exist before the release
          # that publishes them, so this cannot run in the per-PR gate.
          stamp-catalog = pkgs.writeShellApplication {
            name = "stamp-catalog";
            runtimeInputs = with pkgs; [
              jq
              skopeo
              git
              gnugrep
              gnused
              coreutils
            ];
            text = builtins.readFile ./scripts/stamp-catalog.sh;
          };
          # Writes the SPDX licence register to catalog/spdx.gen.libsonnet, which
          # catalog.jsonnet validates every licence value against. The list comes
          # from the devShell (pinned by flake.lock), so this is offline and
          # check-catalog reruns it in the per-PR gate.
          gen-spdx = pkgs.writeShellApplication {
            name = "gen-spdx";
            runtimeInputs = with pkgs; [
              jq
              go-jsonnet
              coreutils
            ];
            text = ''
              export SPDX_LICENSE_LIST_DATA=${pkgs.spdx-license-list-data.json}
              ${builtins.readFile ./scripts/gen-spdx.sh}
            '';
          };
          # Asks each workload's upstream forge for the project's licence and
          # name, into catalog/forge.gen.libsonnet. Network-bound and rate
          # limited without a GITHUB_TOKEN, so it runs on demand / on a schedule.
          gen-forge = pkgs.writeShellApplication {
            name = "gen-forge";
            runtimeInputs = with pkgs; [
              curl
              jq
              go-jsonnet
              gnugrep
              coreutils
            ];
            text = builtins.readFile ./scripts/gen-forge.sh;
          };
          # Reads each workload's image labels from the registry into
          # catalog/upstream.gen.libsonnet (license, source repository, title).
          # Hits the network, so it is run on demand / on a schedule.
          gen-upstream = pkgs.writeShellApplication {
            name = "gen-upstream";
            runtimeInputs = with pkgs; [
              skopeo
              jq
              gnugrep
              coreutils
            ];
            text = builtins.readFile ./scripts/gen-upstream.sh;
          };
          # Generates a live-cluster e2e scenario + thin workflow for every
          # standalone workload from the catalog, and the coverage ledger
          # (hack/smoke/COVERAGE.md). Idempotent and marker-guarded, so it never
          # clobbers a hand-written scenario.
          gen-smoke = pkgs.writeShellApplication {
            name = "gen-smoke";
            runtimeInputs = with pkgs; [
              jq
              gnugrep
              findutils
              coreutils
            ];
            # The emitted scenarios and embedded jq programs carry literal
            # `$(...)` and jq `$vars` in single quotes on purpose — generated text
            # and jq syntax, not shell expansions.
            excludeShellChecks = [ "SC2016" "SC2318" ];
            text = builtins.readFile ./scripts/gen-smoke.sh;
          };
          check-catalog = pkgs.writeShellApplication {
            name = "check-catalog";
            runtimeInputs = with pkgs; [
              go-jsonnet
              jsonnet-bundler
              diffutils
              coreutils
              git
              jq
              gnugrep
              gen-maturity
              gen-spdx
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
          # Renders the deploy examples embedded in workload READMEs and
          # validates every manifest with kubeconform, so a stale or malformed
          # README example fails the gate rather than shipping as broken copy.
          check-readme-examples = pkgs.writeShellApplication {
            name = "check-readme-examples";
            runtimeInputs = with pkgs; [
              go-jsonnet
              jsonnet-bundler
              jq
              kubeconform
              coreutils
              gnused
              python3
            ];
            text = builtins.readFile ./scripts/check-readme-examples.sh;
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
          # Splices the maturity badge and JaaS/stageset deploy walkthrough into
          # every workload README from the catalog.
          gen-readme = pkgs.writeShellApplication {
            name = "gen-readme";
            runtimeInputs = with pkgs; [
              go-jsonnet
              python3
              coreutils
            ];
            text = builtins.readFile ./scripts/gen-readme.sh;
          };
          # Fails if any committed README's generated section is stale.
          check-readme = pkgs.writeShellApplication {
            name = "check-readme";
            runtimeInputs = [ gen-readme ];
            text = builtins.readFile ./scripts/check-readme.sh;
          };
          # Projects one workload's catalogue entry into a standalone document,
          # published beside that workload's own artifact so the description and
          # the thing it describes cannot disagree.
          gen-workload-metadata = pkgs.writeShellApplication {
            name = "gen-workload-metadata";
            runtimeInputs = with pkgs; [
              jq
              coreutils
            ];
            text = builtins.readFile ./scripts/gen-workload-metadata.sh;
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
          # Runs every gate locally (the serial equivalent of CI's parallel
          # jobs); its runtimeInputs are the other commands plus the shared lint
          # gate from the metio/ci flake.
          verify = pkgs.writeShellApplication {
            name = "verify";
            runtimeInputs = [
              check-fmt
              check-catalog
              check-readme
              check-tests
              check-examples
              check-readme-examples
              check-coverage
              check-security
            ]
            ++ devshell.lib.lintTools pkgs;
            text = builtins.readFile ./scripts/verify.sh;
          };
          # Walks an authored workload through every generator in the order the
          # data flows between them, then the gate. checklist.md is the prose
          # around it — the judgement calls (is it carryable, what does the
          # trademark policy say) stay with a person.
          onboard-workload = pkgs.writeShellApplication {
            name = "onboard-workload";
            runtimeInputs = [
              check-tests
              check-catalog
              gen-architectures
              gen-upstream
              gen-signatures
              gen-maturity
              gen-smoke
              gen-readme
              verify
            ]
            ++ (with pkgs; [
              go-jsonnet
              jsonnet-bundler
              jq
              git
              gnugrep
              coreutils
            ]);
            text = builtins.readFile ./scripts/onboard-workload.sh;
          };
          commands = [
            check-fmt
            check-catalog
            check-readme
            check-tests
            check-assembler
            check-examples
            check-readme-examples
            check-coverage
            check-security
            gen-maturity
            gen-spdx
            stamp-catalog
            gen-architectures
            gen-signatures
            gen-forge
            gen-upstream
            gen-bsi
            gen-readme
            gen-workload-metadata
            gen-smoke
            gen-docs-data
            onboard-workload
            verify
          ];
        in
        {
          default = devshell.lib.mkDevShell {
            inherit pkgs;
            packages = kurlyTools ++ securityTools ++ smokeTools ++ docsTools ++ renovateTools ++ commands;
            # The devShell pins every tool and inherited the LOCALE from whoever
            # started it, which is not a detail: collation decides how a glob
            # expands and how sort orders, so a generated file came out with
            # `calibre-web` before `calibre` on a machine whose locale ignores
            # punctuation and after it on one that does not. Both were correct
            # and the drift checks failed on the difference — a gate red for no
            # reason other than which computer ran it.
            #
            # LC_COLLATE rather than LC_ALL, so ordering is byte-wise everywhere
            # while text stays UTF-8: these sources are full of em dashes, and a
            # C locale would have tools treat them as bytes.
            env.LC_COLLATE = "C";
            menu = ''
              echo "kurly commands (also: nix develop --command <name>):"
              echo "  check-fmt        jsonnetfmt --test across all sources"
              echo "  check-catalog    regenerate catalog/catalog.json, fail if stale"
              echo "  check-readme     fail if a workload README's generated section is stale"
              echo "  check-tests      assertion suite + the requiresService negative check"
              echo "  check-examples   render examples + workloads, validate with kubeconform"
              echo "  check-readme-examples  render workload README examples, validate with kubeconform"
              echo "  check-coverage   render every catalog composition, validate with kubeconform"
              echo "  check-security   conftest Rego policy + pluto (deprecated APIs) + kubesec"
              echo "  gen-maturity     derive workload maturity tiers (checked by check-catalog)"
              echo "  gen-spdx         write the SPDX licence register (checked by check-catalog)"
              echo "  gen-architectures  derive each image's CPU architectures from the registry"
              echo "  gen-signatures   derive whether each image is signed, and by whom"
              echo "  gen-readme       splice the deploy walkthrough into every workload README"
              echo "  gen-workload-metadata  one workload's catalogue entry, as its own document"
              echo "  gen-docs-data    stage catalog.json into docs/data/ for the site"
              echo "  onboard-workload <name>  run every generator for a new workload, in order"
              echo "  verify           run every gate locally (what CI runs)"
            '';
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
