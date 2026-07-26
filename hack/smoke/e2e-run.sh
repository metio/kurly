#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The single e2e pipeline. It runs on ONE kind cluster (latest Kubernetes) with
# ONE install of the latest Flux, JaaS, and stageset-controller, then walks the
# workloads a PR changed relative to the default branch. For each changed
# workload it runs the FAST check (boot the workload directly and wait for health)
# and then the DEEP check (deliver it through Flux -> JaaS -> stageset and wait for
# the rollout). Unchanged workloads are skipped. The result is one long-running
# pipeline, never hundreds of parallel jobs.
#
# BASE_REF   the default branch to diff against (default: main)
# WORKLOADS  an explicit space-separated selection (a manual dispatch); overrides
#            change detection and runs exactly those.
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

mapfile -t changed < <(kurly::changed_workloads)
if [ "${#changed[@]}" -eq 0 ]; then
  echo "no workloads changed — nothing to run"
  exit 0
fi
echo "changed workloads (${#changed[@]}): ${changed[*]}"

kurly::vendor
# The deep-check stack, latest of each, installed once for the whole walk.
kurly::install_flux
kurly::install_jaas
kurly::install_stageset
kurly::install_registry
# The kurly library image every deep snippet imports — built and pushed once.
kurly::publish_images

failed=()
for id in "${changed[@]}"; do
  scenario="hack/smoke/scenario-${id}.sh"
  if [ ! -f "$scenario" ]; then
    echo "::warning::${id} changed but has no scenario — skipping"
    continue
  fi
  echo "::group::e2e ${id}"
  ok=true
  echo "== FAST ${id} =="
  bash "$scenario" || { echo "::error::fast check failed for ${id}"; ok=false; }
  if [ "$ok" = true ]; then
    kurly::deep "$id" || { echo "::error::deep check failed for ${id}"; ok=false; }
  fi
  [ "$ok" = true ] || failed+=("$id")
  echo "::endgroup::"
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "::error::e2e failed for: ${failed[*]}"
  exit 1
fi
echo "e2e passed for all changed workloads: ${changed[*]}"
