#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Which Pod Security Standards bar the pods an OPERATOR creates clear, for the
# stages that render only a custom resource.
#
# Those stages publish `pss: null`, and that is correct: PSS collapses to one
# level, and a level computed from the pod securityContext a CRD happens to
# expose would be a claim about containers kurly never wrote. Most of the
# standard is checked per CONTAINER — allowPrivilegeEscalation, capabilities,
# runAsNonRoot — and the containers belong to the operator.
#
# So this measures instead of deriving, the way cr-bsi.sh does for bollwerk:
# install the operator, apply the stage, let the operator produce real pods, and
# evaluate THOSE.
#
# Two differences from cr-bsi.sh, both deliberate:
#
#   IT DOES NOT STRIP THE POD. cr-bsi.sh removes volumes and mounts so that a
#   dry-run CREATE does not fail on objects that are not there. PSS READS THE
#   VOLUMES — hostPath fails baseline, and restricted allows only eight volume
#   types — so a stripped pod would come back cleaner than the real one. That is
#   the failure this whole file exists to avoid, so the pod is evaluated exactly
#   as the API server stored it.
#
#   IT NEEDS NO API SERVER TO JUDGE. The evaluation is jsonnet over a pod spec,
#   not an admission round trip, so there is no dry-run and nothing to submit.
#   The cluster is needed only to get the pods.
#
#   cr-pss.sh <outdir> <workload/stage>...
set -uo pipefail

OUT="$1"
shift
mkdir -p "$OUT"
cd "$(dirname "$0")/../../.." || exit 1

POD_WAIT=${POD_WAIT:-300}

measure_one() {
  local key="$1" w="${1%%/*}" st="${1##*/}"
  local res="$OUT/${w}__${st}.json"
  local ns="kurly-pss-${w}"

  kubectl delete namespace "$ns" --ignore-not-found --wait=true >/dev/null 2>&1
  local waited=0
  while kubectl get namespace "$ns" >/dev/null 2>&1; do
    sleep 3
    waited=$((waited + 3))
    [ "$waited" -lt 180 ] || break
  done
  kubectl create namespace "$ns" >/dev/null 2>&1

  local render="$OUT/.render-${w}-${st}.json"
  if ! jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import 'workloads/${w}/${st}.libsonnet')())" \
    >"$render" 2>/dev/null; then
    printf '{"stage":"%s","verdict":"render-failed"}\n' "$key" >"$res"
    echo "  ${key}: render-failed"
    return 0
  fi

  # A stage naming its own namespace is a cluster add-on and must be applied
  # where it says — the same rule cr-bsi.sh and deep-run.sh follow.
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

  # Every pod the operator made, exactly as stored. The whole set is evaluated
  # together and the verdict is the WEAKEST of them: a workload's security is the
  # security of its worst pod, and reporting the best one would be picking the
  # answer we liked.
  local specs="$OUT/.pods-${w}-${st}.json"
  kubectl -n "$ns" get pods -o json 2>/dev/null | jq '[.items[] | {spec}]' >"$specs"
  local count
  count="$(jq 'length' "$specs" 2>/dev/null || echo 0)"
  if [ "${count:-0}" = 0 ]; then
    printf '{"stage":"%s","verdict":"no-pods"}\n' "$key" >"$res"
    echo "  ${key}: no-pods"
    kubectl delete namespace "$ns" --ignore-not-found --wait=false >/dev/null 2>&1
    return 0
  fi

  # Each pod judged on its own, then the weakest kept — rather than handing the
  # evaluator every pod at once, which would report one merged verdict and lose
  # which pod earned it.
  jsonnet -J vendor \
    --ext-str stage="$key" \
    --ext-code pods="$(cat "$specs")" \
    -e 'local pss = import "catalog/pss.libsonnet";
        local pods = std.extVar("pods");
        local rank = { restricted: 3, baseline: 2, privileged: 1 };
        local each = [pss.ofPods([p]) for p in pods];
        local weakest = std.foldl(
          function(acc, v) if acc == null || rank[v.level] < rank[acc.level] then v else acc,
          each, null
        );
        {
          stage: std.extVar("stage"),
          pods: std.length(pods),
          level: weakest.level,
          violates: weakest.violates,
        }' >"$res" 2>/dev/null \
    || { printf '{"stage":"%s","verdict":"evaluate-failed"}\n' "$key" >"$res"; echo "  ${key}: evaluate-failed"; return 0; }

  echo "  ${key}: $(jq -r '"\(.level)  (\(.pods) pod(s))\(if (.violates|length) > 0 then "  violates: " + (.violates|join(", ")) else "" end)"' "$res")"
  kubectl delete namespace "$ns" --ignore-not-found --wait=false >/dev/null 2>&1
}

for key in "$@"; do
  measure_one "$key"
done

# The ledger the catalogue imports. Only stages that produced a VERDICT are
# written: one whose operator would not install, or whose custom resource creates
# no pod, has no answer, and recording a blank would read as a clean one.
#
# Entries this run did not measure are carried over from the committed file, so a
# partial run — one operator down, one stage retried — narrows rather than
# retracts, which is what makes rerunning a subset safe.
if [ "${WRITE_LEDGER:-1}" = 1 ]; then
  ledger=catalog/pss-operator.gen.libsonnet
  previous="$(mktemp)"
  if [ -f "$ledger" ]; then jsonnet "$ledger" >"$previous" 2>/dev/null || echo '{}' >"$previous"; else echo '{}' >"$previous"; fi
  header="$(sed -n '1,/^{$/p' "$ledger" 2>/dev/null | sed '$d')"
  {
    printf '%s\n{\n' "$header"
    jq -s --slurpfile prev "$previous" '
      ([.[] | select(.level) | {key: .stage, value: {pods: .pods, level: .level, violates: .violates}}] | from_entries) as $now
      | ($prev[0] + $now)
      | to_entries | sort_by(.key)[]
      | "  \(.key | @json): { pods: \(.value.pods), level: \(.value.level | @json), violates: [\(.value.violates | map(@json) | join(", "))] },"
    ' -r "$OUT"/*.json 2>/dev/null | sed "s/\"/'/g"
    printf '}\n'
  } >"${ledger}.new"
  mv "${ledger}.new" "$ledger"
  jsonnetfmt --in-place "$ledger"
  echo "wrote ${ledger} ($(grep -c 'level:' "$ledger") stages measured)"
  rm -f "$previous"
fi
echo "cr-pss: done -> $OUT"
