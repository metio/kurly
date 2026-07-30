#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Walks the fleet's DEEP check: for each workload, deliver it the way a consumer
# does — build its source image, let Flux pull it, JaaS render it, and
# stageset-controller apply it — and wait for its controllers to roll out. Every
# workload that comes up green is recorded, with the date, in
# catalog/delivered-verified.libsonnet — the evidence behind the catalog's
# `maturity.delivered`, an axis of its own rather than a rung on the tier ladder.
#
# The walk is RESUMABLE and the ledger is written after each workload, not at the
# end: a run killed halfway keeps everything it proved. Re-running skips what is
# already recorded unless FORCE=1.
#
#   ./hack/smoke/deep-run.sh                 walk every catalogued workload
#   ./hack/smoke/deep-run.sh tik valkey      walk exactly these
#   FORCE=1 ./hack/smoke/deep-run.sh tik     re-verify one already recorded
#
# It expects a kind cluster whose node maps the registry NodePort to
# localhost:5001 (hack/smoke/kind-registry-config.yaml) — kurly::publish_images
# pushes over that port.
set -euo pipefail
cd "$(dirname "$0")/../.."
# A contributor's ~/.kube/kuberc defaults (server-side apply, interactive delete)
# would make this diverge from CI, which has none.
export KUBERC=/dev/null
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

ledger=catalog/delivered-verified.libsonnet
today="$(date +%F)"

# The workloads already proven, one per line — the resume set, read from the
# ledger with the same key extraction gen-maturity uses.
# An empty ledger is the normal starting state, so a no-match grep must not fail
# the walk before it starts.
recorded() { { grep -oE "^  '?[a-z0-9-]+'?:" "$ledger" 2>/dev/null || true; } | tr -d " ':" | sort -u; }

# Rewrites the ledger from its current entries plus <id>=<date>. Rewriting the
# whole object rather than splicing a line keeps it sorted and jsonnetfmt-clean
# however many times the walk is interrupted and resumed.
record() {
  local id="$1" tmp entries
  # Existing "id date" pairs, minus the one being written (a re-verify moves the
  # date forward rather than duplicating the key).
  entries="$(grep -oE "^  '?[a-z0-9-]+'?: '[0-9-]+'," "$ledger" 2>/dev/null \
    | sed -E "s/^  '?([a-z0-9-]+)'?: '([0-9-]+)',$/\1 \2/" | grep -v "^${id} " || true)"
  entries="$(printf '%s\n%s %s\n' "$entries" "$id" "$today" | grep -v '^$' | LC_ALL=C sort)"
  tmp="$(mktemp)"
  # Everything above the opening brace is the file's prose header, kept verbatim.
  sed -n '1,/^{$/p' "$ledger" >"$tmp"
  while read -r name date; do
    # jsonnetfmt quotes a key only when it must — anything that is not a bare
    # identifier, which for workload names means a leading digit (2fauth) or a
    # hyphen (uptime-kuma). Match that exactly, or check-fmt fails on the file this
    # walk just wrote.
    case "$name" in
      [A-Za-z_]*) : ;;
      *) printf "  '%s': '%s',\n" "$name" "$date" >>"$tmp"; continue ;;
    esac
    case "$name" in
      *[!A-Za-z0-9_]*) printf "  '%s': '%s',\n" "$name" "$date" >>"$tmp" ;;
      *) printf "  %s: '%s',\n" "$name" "$date" >>"$tmp" ;;
    esac
  done <<<"$entries"
  printf '}\n' >>"$tmp"
  mv "$tmp" "$ledger"
}

if [ "$#" -gt 0 ]; then
  targets=("$@")
else
  mapfile -t targets < <(jq -r '.workloads[].id' catalog/catalog.json | LC_ALL=C sort)
fi

skip="$(recorded)"
kurly::vendor
kurly::install_flux
kurly::install_jaas
kurly::install_stageset
kurly::install_registry
kurly::publish_images

delivered=0 skipped=0
failed=()
for id in "${targets[@]}"; do
  if [ -z "${FORCE:-}" ] && grep -qx "$id" <<<"$skip"; then
    skipped=$((skipped + 1))
    continue
  fi
  echo "::group::deep ${id}"
  # Start every workload from an empty namespace, by DELETING it rather than
  # waiting for a deletion nobody asked for. A walk that is killed mid-workload
  # leaves the namespace Active and full of that attempt's objects; a wait then
  # returns at once, kurly::deep applies over the top, and the run reads a verdict
  # computed against a previous attempt's failed Deployment — baserow was
  # diagnosed with pods 55 minutes older than the run looking at them.
  #
  # Finalizers are stripped first: the StageSet and JsonnetSnippet hold them, and
  # a namespace deleted while a controller cannot authenticate to release them
  # never finishes terminating.
  if kubectl get namespace "kurly-deep-${id}" >/dev/null 2>&1; then
    echo "== ${id}: a namespace from an earlier attempt is still here — clearing it =="
    kubectl --namespace="kurly-deep-${id}" get stageset,jsonnetsnippet -o name 2>/dev/null \
      | xargs -r -I{} kubectl --namespace="kurly-deep-${id}" patch {} --type=merge \
        -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
    kubectl delete namespace "kurly-deep-${id}" --interactive=false --timeout=240s >/dev/null 2>&1 || true
  fi
  kubectl wait --for=delete "namespace/kurly-deep-${id}" --timeout=180s >/dev/null 2>&1 || true
  ok=true
  kurly::deep "$id" || ok=false
  # BOTH controllers act by impersonating a ServiceAccount in the workload's
  # namespace — JaaS as the tenant SA to render, stageset as stageset-deployer to
  # apply — and both key that credential by namespace and hold on to it. A walk
  # deletes and recreates kurly-deep-<id> whenever it revisits a workload, and a
  # credential minted for the previous incarnation is rejected 401 against the new
  # one. Neither re-mints on its own, so everything in that namespace fails
  # Unauthorized no matter how sound the workload is: JaaS reports
  # SourceFetchFailed on the snippet, stageset reports StageFailed on a dry-run
  # apply. Restarting the controller that is holding the stale credential drops it.
  #
  # BOTH are restarted whenever EITHER reports it, because the namespace being
  # recreated staled both caches at the same instant — but the two failures can
  # only surface one at a time. JaaS renders first, so its 401 is what a run sees;
  # restart only JaaS and the render succeeds, the apply then meets stageset's own
  # stale credential, and the single retry has already been spent. Restarting the
  # pair costs one rollout and turns two serial discoveries into none.
  stale=false
  if [ "$ok" = false ]; then
    kubectl --namespace="kurly-deep-${id}" get jsonnetsnippet,stageset \
      -o jsonpath='{.items[*].status.conditions[*].message}' 2>/dev/null \
      | grep -q Unauthorized && stale=true
  fi
  if [ "$stale" = true ]; then
    echo "== ${id}: a stale impersonation credential — restarting both controllers and retrying =="
    kubectl --namespace=jaas-system rollout restart deploy/jaas >/dev/null 2>&1 || true
    kubectl --namespace=stageset-system rollout restart deploy >/dev/null 2>&1 || true
    kubectl --namespace=jaas-system rollout status deploy/jaas --timeout=180s >/dev/null 2>&1 || true
    kubectl --namespace=stageset-system rollout status deploy --timeout=180s >/dev/null 2>&1 || true
    ok=true
    kurly::deep "$id" || ok=false
  fi
  if [ "$ok" = true ]; then
    # kurly::deep returns 0 both for a delivered workload and for one it skipped
    # as having no controller (a custom-resource stage). Only the former is
    # evidence, so the ledger is written from what actually exists in the cluster:
    # a StageSet that went Ready.
    if [ -n "$(kubectl --namespace="kurly-deep-${id}" get stageset -o name 2>/dev/null || true)" ]; then
      record "$id"
      delivered=$((delivered + 1))
      echo "recorded ${id} as delivered (${today})"
    else
      echo "::notice::${id} renders no controller — nothing to deliver, so no record"
    fi
  else
    failed+=("$id")
    echo "::error::deep check failed for ${id}"
  fi
  # BEFORE the namespace sweep, not after: the StageSet and the JsonnetSnippet carry
  # controller finalizers, and both controllers run their cleanup by impersonating
  # the tenant ServiceAccount. Once the namespace is Terminating its RBAC can be
  # collected first, and the finalizer then fails Unauthorized forever — the
  # namespace never finishes deleting, and the next run of this workload has every
  # object it applies rejected Forbidden. Deleting them while their Role still
  # exists is what keeps the walk repeatable.
  kubectl --namespace="kurly-deep-${id}" delete stageset,jsonnetsnippet --all \
    --interactive=false --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
  kurly::cleanup_workload "$id"
  # Last resort: a finalizer that is already wedged (a run killed mid-cleanup) would
  # otherwise leave the namespace Terminating for the rest of the session.
  if kubectl get namespace "kurly-deep-${id}" >/dev/null 2>&1; then
    echo "== ${id}: namespace still terminating — stripping stuck finalizers =="
    kubectl --namespace="kurly-deep-${id}" get stageset,jsonnetsnippet -o name 2>/dev/null \
      | xargs -r -I{} kubectl --namespace="kurly-deep-${id}" patch {} --type=merge \
        -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
    kubectl wait --for=delete "namespace/kurly-deep-${id}" --timeout=120s >/dev/null 2>&1 || true
  fi
  echo "::endgroup::"
done

echo "deep-run: ${delivered} newly delivered, ${skipped} already recorded, ${#failed[@]} failed"
if [ "${#failed[@]}" -gt 0 ]; then
  echo "::error::deep check failed for: ${failed[*]}"
  exit 1
fi
