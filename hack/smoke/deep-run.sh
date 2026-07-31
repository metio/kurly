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

# Workloads with a diagnosis already made, and why — hack/smoke/known-failures.txt.
# The walk remembers successes and nothing else, so without this each of them is
# re-attempted every pass at roughly fifteen minutes a time. A skip is NOT a pass:
# every one is named at the start and the end, and the run exits non-zero while any
# remain. RETRY=1 attempts them anyway, and naming a workload explicitly always
# runs it — an entry must never be able to silence a deliberate request.
knownfile=hack/smoke/known-failures.txt
declare -A known_reason=()
if [ -f "$knownfile" ] && [ -z "${RETRY:-}" ] && [ "$#" -eq 0 ]; then
  while read -r kid kreason; do
    case "$kid" in ''|\#*) continue ;; esac
    known_reason["$kid"]="$kreason"
  done < <(sed 's/#.*//' "$knownfile")
fi
if [ "${#known_reason[@]}" -gt 0 ]; then
  echo "== skipping ${#known_reason[@]} workloads whose cause is already known (RETRY=1 to attempt them) =="
  for kid in $(printf '%s\n' "${!known_reason[@]}" | LC_ALL=C sort); do
    printf '   %-20s %s\n' "$kid" "${known_reason[$kid]}"
  done
fi

skip="$(recorded)"
kurly::vendor
kurly::install_flux
kurly::install_jaas
kurly::install_stageset
kurly::install_registry
kurly::publish_images

delivered=0 skipped=0 knownskipped=0
failed=()

# The namespace of the workload being walked right now, so an interrupted run does
# not leave it behind. The loop already clears a stale namespace before RE-running
# a workload, which keeps the verdict honest; this is about the resources, and it
# only self-heals for a workload that is attempted again. One that lands on the
# skip list never is — mongo-express sat Active for an hour and a half, two pods
# in CrashLoopBackOff and a database beside them, because the walk was killed
# during it and then skipped ever after.
inflight=""
kurly::drop_inflight() {
  local rc=$?
  if [ -n "$inflight" ]; then
    echo "== interrupted during ${inflight}: removing its namespace =="
    # --wait=false: a signal wants a prompt exit, and the terminating namespace
    # finishes on its own.
    kubectl delete namespace "kurly-deep-${inflight}" \
      --interactive=false --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
  exit "$rc"
}
trap kurly::drop_inflight INT TERM

for id in "${targets[@]}"; do
  if [ -z "${FORCE:-}" ] && grep -qx "$id" <<<"$skip"; then
    skipped=$((skipped + 1))
    continue
  fi
  if [ -n "${known_reason[$id]:-}" ]; then
    echo "== skip ${id}: ${known_reason[$id]} =="
    knownskipped=$((knownskipped + 1))
    continue
  fi
  echo "::group::deep ${id}"
  inflight="$id"
  # Start every workload from an empty namespace. A walk killed mid-workload leaves
  # it Active and full of that attempt's objects; a wait alone returns at once and
  # the run would read a verdict computed against a previous attempt.
  #
  # No finalizer stripping: both controllers now force-drop a finalizer as soon as
  # the withdraw or teardown fails for a cause no retry can clear, so a namespace
  # finishes terminating on its own. If one hangs here, that is a NEW bug worth
  # reporting with the finalizer and object named — not something to paper over.
  if kubectl get namespace "kurly-deep-${id}" >/dev/null 2>&1; then
    echo "== ${id}: a namespace from an earlier attempt is still here — clearing it =="
    kubectl delete namespace "kurly-deep-${id}" --interactive=false --timeout=240s >/dev/null 2>&1 || true
  fi
  kubectl wait --for=delete "namespace/kurly-deep-${id}" --timeout=180s >/dev/null 2>&1 || true
  ok=true
  kurly::deep "$id" || ok=false
  # A 401 is now genuinely interesting. Both controllers evict the cached tenant
  # credential on one, mint a fresh one and retry the call, so a stale credential
  # costs a retry rather than a failure and never reaches a status message. One
  # that DOES reach a message survived a re-mint, which no restart here would fix
  # and which the runbooks say to read rather than guess at:
  #   https://stageset.projects.metio.wtf/runbooks/stagefailed/     (the apply)
  #   https://jaas.projects.metio.wtf/runbooks/sourcefetchfailed/   (the render)
  #
  # So this prints evidence and stops, where it used to restart both controllers
  # and try again. Leaving that workaround in would hide exactly this case.
  if [ "$ok" = false ] \
    && kubectl --namespace="kurly-deep-${id}" get jsonnetsnippet,stageset \
         -o jsonpath='{.items[*].status.conditions[*].message}' 2>/dev/null | grep -q Unauthorized; then
    echo "::error::${id}: an Unauthorized survived the controllers' own re-mint — this is a new cause, not a stale credential"
    echo "::group::${id}: Unauthorized evidence"
    kubectl --namespace="kurly-deep-${id}" get serviceaccount stageset-deployer default \
      -o custom-columns=NAME:.metadata.name,UID:.metadata.uid,CREATED:.metadata.creationTimestamp 2>&1 || true
    kubectl --namespace="kurly-deep-${id}" get stageset,jsonnetsnippet \
      -o jsonpath='{range .items[*]}{.kind}{" "}{.metadata.name}{" "}{.status.conditions[*].message}{"\n"}{end}' 2>&1 || true
    kubectl --namespace=stageset-system logs deploy/stageset-controller --tail=100 2>/dev/null | grep -i unauthor || echo "(none)"
    kubectl --namespace=jaas-system logs deploy/jaas --tail=100 2>/dev/null | grep -i unauthor || echo "(none)"
    echo "::endgroup::"
  fi
  if [ "$ok" = true ]; then
    # kurly::deep returns 0 both for a delivered workload and for one it skipped
    # as having no controller (a custom-resource stage). Only the former is
    # evidence, so the ledger is written from what actually exists in the cluster:
    # a StageSet that went Ready.
    if [ -n "$(kubectl --namespace="kurly-deep-${id}" get stageset -o name 2>/dev/null || true)" ]; then
      # Ask the database whether the workload actually used it. Warns only: the
      # record below stands on the rollout, which is what `delivered` claims.
      kurly::verify_database "kurly-deep-${id}" "$id"
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
  # No finalizer dance before or after: the controllers force-drop on their own
  # now, so deleting the namespace is enough.
  inflight=""
  kurly::cleanup_workload "$id"
  kubectl delete namespace "kurly-deep-${id}" --interactive=false --ignore-not-found --timeout=240s >/dev/null 2>&1 || true
  echo "::endgroup::"
done

echo "deep-run: ${delivered} newly delivered, ${skipped} already recorded, ${knownskipped} skipped with a known cause, ${#failed[@]} failed"
if [ "$knownskipped" -gt 0 ]; then
  echo "::warning::${knownskipped} workloads were skipped with a known cause and are NOT proven — see ${knownfile}"
  for kid in $(printf '%s\n' "${!known_reason[@]}" | LC_ALL=C sort); do echo "  skipped: ${kid}"; done
fi
# A workload that is listed AND delivered means the list is stale, which would
# hide a workload that now passes. Say so loudly rather than leaving it to rot.
for kid in "${!known_reason[@]}"; do
  if grep -qE "^  '?${kid}'?:" "$ledger"; then
    echo "::warning::${kid} is in ${knownfile} but the ledger says it delivered — remove the entry"
  fi
done
if [ "${#failed[@]}" -gt 0 ]; then
  echo "::error::deep check failed for: ${failed[*]}"
  exit 1
fi
