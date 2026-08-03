#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Deep-tier BSI for CUSTOM-RESOURCE stages.
#
# bollwerk's policies select pods, workloads and a few core kinds — never a
# Prometheus or a CNPG Cluster. So a CR stage renders nothing they can judge,
# and the catalogue says applicable:false. That is true and it is not the whole
# story: `pods` IS in scope, so the pod the OPERATOR creates is subject to
# admission on a real cluster, and nothing here has ever measured it.
#
# The obstacle is that an admission warning goes to whoever created the object.
# When the operator creates the pod, the warning lands in the operator's client,
# not ours. So this takes the pod the operator actually produced, strips what
# only exists because it is running, and submits it again as a dry-run CREATE —
# the same policies then evaluate the same spec and warn to us.
#
# What is measured is therefore the OPERATOR's pod, not kurly's manifest: the
# answer says whether the thing that ends up running would be admitted.
#
#   cr-bsi.sh <outdir> <workload/stage>...
set -uo pipefail

OUT="$1"
shift
mkdir -p "$OUT"
# Run from the repository root, like the other deep scenarios.
cd "$(dirname "$0")/../../.." || exit 1

# How long to wait for an operator to turn a CR into pods. Operators reconcile on
# their own schedule and some pull a large image first.
POD_WAIT=${POD_WAIT:-300}

measure_one() {
  local key="$1" w="${1%%/*}" st="${1##*/}"
  local res="$OUT/${w}__${st}.json"
  local ns="kurly-cr-${w}"

  kubectl delete namespace "$ns" --ignore-not-found --wait=true >/dev/null 2>&1
  local waited=0
  while kubectl get namespace "$ns" >/dev/null 2>&1; do
    sleep 3
    waited=$((waited + 3))
    [ "$waited" -lt 180 ] || break
  done
  kubectl create namespace "$ns" >/dev/null 2>&1

  local render="$OUT/.cr-${w}-${st}.json"
  if ! jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import 'workloads/${w}/${st}.libsonnet')())" \
    >"$render" 2>/dev/null; then
    printf '{"stage":"%s","verdict":"render-failed"}\n' "$key" >"$res"
    echo "  ${key}: render-failed"
    return 0
  fi

  # A stage that names its own namespace is a cluster add-on and must be applied
  # where it says — prometheus puts everything in `monitoring`, and forcing it
  # elsewhere fails the apply outright. The same rule deep-run.sh follows.
  local declared
  declared="$(jq -r '[.items[].metadata.namespace // empty] | unique | .[0] // empty' "$render")"
  if [ -n "$declared" ]; then
    ns="$declared"
    kubectl create namespace "$ns" >/dev/null 2>&1
  fi
  if ! kubectl apply --namespace="$ns" --filename="$render" >/dev/null 2>&1; then
    printf '{"stage":"%s","verdict":"cr-rejected"}\n' "$key" >"$res"
    echo "  ${key}: cr-rejected (operator or CRD missing)"
    return 0
  fi

  # Wait for the operator to produce pods.
  local n=0 pods=""
  while [ "$n" -lt "$POD_WAIT" ]; do
    pods="$(kubectl -n "$ns" get pods -o name 2>/dev/null)"
    [ -n "$pods" ] && break
    sleep 5
    n=$((n + 5))
  done
  if [ -z "$pods" ]; then
    printf '{"stage":"%s","verdict":"no-pods"}\n' "$key" >"$res"
    echo "  ${key}: no-pods (operator created none within ${POD_WAIT}s)"
    kubectl delete namespace "$ns" --ignore-not-found --wait=false >/dev/null 2>&1
    return 0
  fi

  # Re-submit each operator-made pod as a dry-run CREATE, under a name of its
  # own so it cannot collide with the live one, and collect what the policies
  # say. Everything the API server fills in is stripped: a pod carrying status,
  # nodeName or a resourceVersion is rejected as invalid before any policy sees
  # it, and that rejection is not a verdict.
  local warnings="" pod
  for pod in $pods; do
    local spec="$OUT/.pod.json"
    kubectl -n "$ns" get "$pod" -o json 2>/dev/null \
      | jq 'del(.status, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp,
                .metadata.ownerReferences, .metadata.generateName, .metadata.managedFields,
                .metadata.annotations, .metadata.labels, .spec.nodeName, .spec.tolerations,
                .spec.volumes, .spec.containers[].volumeMounts, .spec.initContainers[]?.volumeMounts)
             | .metadata.name = "bsi-probe"' >"$spec" 2>/dev/null
    [ -s "$spec" ] || continue
    warnings="${warnings}$(kubectl apply --namespace="$ns" --dry-run=server --filename="$spec" 2>&1 >/dev/null || true)"$'\n'
  done

  local names
  names="$(grep -oP "ValidatingAdmissionPolicy '\K[^']+" <<<"$warnings" | sort -u | paste -sd' ' - || true)"
  local list=""
  local p
  for p in $names; do list="${list:+$list,}\"${p}\""; done
  printf '{"stage":"%s","verdict":"measured","pods":%d,"violates":[%s]}\n' \
    "$key" "$(printf '%s\n' "$pods" | grep -c .)" "$list" >"$res"
  echo "  ${key}: measured — $(printf '%s\n' "$pods" | grep -c .) pod(s), violates: ${names:-none}"
  # Only a namespace this run created is torn down; a stage's own namespace
  # (monitoring) may hold things that were there first.
  case "$ns" in kurly-cr-*) kubectl delete namespace "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 ;; esac
}

for key in "$@"; do
  echo "== ${key} =="
  measure_one "$key"
done

# The ledger the catalogue imports, assembled from the per-stage results. Only
# MEASURED stages are written: a stage whose operator would not run, or whose CR
# creates no pod, has no verdict, and recording a blank for it would read as a
# clean one. The header says which kind of absence each is.
#
# Entries this run did not measure are carried over from the committed file, so a
# partial run — one operator down, one stage retried — narrows rather than
# retracts. Rerunning a subset is then safe, which is what makes it usable from a
# schedule.
if [ "${WRITE_LEDGER:-1}" = 1 ]; then
  ledger=catalog/bsi-operator.gen.libsonnet
  previous="$(mktemp)"
  if [ -f "$ledger" ]; then jsonnet "$ledger" >"$previous" 2>/dev/null || echo '{}' >"$previous"; else echo '{}' >"$previous"; fi
  header="$(sed -n '1,/^{$/p' "$ledger" 2>/dev/null | sed '$d')"
  {
    printf '%s\n{\n' "$header"
    jq -s --slurpfile prev "$previous" '
      ([.[] | select(.verdict == "measured") | {key: .stage, value: {pods: .pods, violates: .violates}}] | from_entries) as $now
      | ($prev[0] + $now)
      | to_entries | sort_by(.key)[]
      | "  \(.key | @json): { pods: \(.value.pods), violates: [\(.value.violates | map(@json) | join(", "))] },"
    ' -r "$OUT"/*.json 2>/dev/null | sed "s/\"/'/g; s/'\([a-z0-9-]*\/[a-z0-9-]*\)':/'\1':/"
    printf '}\n'
  } >"${ledger}.new"
  mv "${ledger}.new" "$ledger"
  jsonnetfmt --in-place "$ledger"
  echo "wrote ${ledger} ($(grep -c 'pods:' "$ledger") stages measured)"
  rm -f "$previous"
fi
echo "cr-bsi: done ($# stages) -> $OUT"
