# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The Kubernetes static-analysis gate, weighted toward custom policy. Renders
# every example and workload, splits each into per-manifest files, then:
#   - conftest runs kurly's own invariants (policy/*.rego) over every manifest —
#     the primary gate, precise and free of ignore-list upkeep;
#   - pluto flags any removed or deprecated API version;
#   - kubesec scores the hardened workload controllers for security risk.
# kurly bakes in the hardened defaults these check, so its output passes and the
# gate guards that. The security-RELAXATION examples (legacy runs a baseline
# image, cron writes a scratch filesystem) exist to demonstrate the escape
# hatches, so they are exempt from the security SCORE — but still policy-checked.

# k8s-libsonnet floats at upstream HEAD; vendor it fresh so the gate checks what
# clusters actually run, and symlink the repo into the vendor tree so workloads
# resolve kurly's canonical import path the way JaaS does in-cluster.
[ "${KURLY_VENDORED:-}" = "1" ] || jb install
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mandir="$workdir/manifests"
mkdir -p "$mandir"

# Render every example and workload in ONE jsonnet process: a single invocation
# imports k8s-libsonnet once and shares it across every render, instead of paying
# the parse per source — the render cost stops scaling with the workload count.
# An example is a `kind: List`; a workload stage is a composable app rendered with
# defaults and wrapped in kurly.list like a consumer's JsonnetSnippet does.
exprof() {
  case "$1" in
    workloads/*/*.libsonnet) printf "(import 'github.com/metio/kurly/main.libsonnet').list((import '%s')())" "$1" ;;
    *) printf "(import '%s')" "$1" ;;
  esac
}
# Every example and workload by default; just the changed workloads (plus the
# examples) when KURLY_WORKLOADS narrows an incremental run.
if [ -n "${KURLY_WORKLOADS:-}" ]; then
  mapfile -t changed <<<"$KURLY_WORKLOADS"
  sources=(examples/*.jsonnet "${changed[@]}")
else
  sources=(examples/*.jsonnet workloads/*/*.libsonnet)
fi
program="{"
for src in "${sources[@]}"; do
  key="${src//\//-}"; key="${key%.*}"
  program+=$(printf '"%s": %s,' "$key" "$(exprof "$src")")
done
program+="}"
all="$workdir/all.json"
if ! jsonnet -J vendor -e "$program" >"$all" 2>"$workdir/err"; then
  cat "$workdir/err" >&2
  for src in "${sources[@]}"; do
    jsonnet -J vendor -e "$(exprof "$src")" >/dev/null 2>&1 || { echo "::error::$src failed to render"; exit 1; }
  done
  echo "::error::batched render failed (see above)"; exit 1
fi

# Split every manifest into its own file for conftest and pluto — one jq+split
# pass over the whole blob, not one jq per source.
jq -c '.[] | .items[]' "$all" \
  | split --lines=1 --additional-suffix=.json - "$mandir/manifest-"
echo "rendered $(find "$mandir" -name '*.json' | wc -l) manifests"

echo "== conftest (kurly Rego invariants) =="
conftest test --policy policy "$mandir"/*.json

# The cross-manifest invariants read every rendered object at once (--combine),
# under their own namespace so the per-object rules above are unaffected. A
# ServiceMonitor pointed at a port no selected Service exposes is caught here and
# nowhere else — the workload's own config cannot see a port a consumer adds to
# the Service by hand.
echo "== conftest (cross-manifest invariants) =="
conftest test --combine --namespace combined --policy policy "$mandir"/*.json

# Prove that pass actually bites: a ServiceMonitor scraping a port no Service
# exposes must FAIL it. jsonnet has no try/catch and this is a render-time
# cluster fault, not a jsonnet assert, so the only way to observe the guard is to
# feed it a broken pair and require a non-zero exit.
echo "== the cross-manifest ServiceMonitor guard fires on a bad port =="
badpair="$(mktemp -d)"
trap 'rm -rf "$workdir" "$badpair"' EXIT
jsonnet -J vendor -e \
  "local k = import 'github.com/metio/kurly/main.libsonnet';
   k.list(k.http('probe', 'img:1') + k.serviceMonitor(port='nonexistent'))" \
  | jq -c '.items[]' | split --lines=1 --additional-suffix=.json - "$badpair/probe-"
if conftest test --combine --namespace combined --policy policy "$badpair"/*.json >/dev/null 2>&1; then
  echo "::error::cross-manifest guard passed a ServiceMonitor scraping a port no Service exposes" >&2
  exit 1
fi
echo "the guard fires on a ServiceMonitor whose port no Service exposes"

# Prove the no-Secret invariant bites too: a rendered Secret of any shape must
# FAIL the per-object policy. No workload authors one, so the only way to observe
# the guard is to feed it a Secret and require a non-zero exit.
echo "== the no-Secret guard fires on a rendered Secret =="
badsecret="$(mktemp -d)"
trap 'rm -rf "$workdir" "$badpair" "$badsecret"' EXIT
printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"leaked"},"stringData":{"token":"hunter2"}}' \
  > "$badsecret/secret.json"
if conftest test --policy policy "$badsecret"/secret.json >/dev/null 2>&1; then
  echo "::error::no-Secret guard passed a rendered Secret" >&2
  exit 1
fi
echo "the guard fires on a rendered Secret"

echo "== pluto (removed / deprecated APIs) =="
pluto detect-files --directory "$mandir" --target-versions k8s=v1.31.0

# kubesec scores the hardened controllers; a drop below the floor is a security
# regression (a missing readOnlyRootFilesystem / dropped-capabilities / seccomp).
# kubesec has no batch mode and a single scan costs ~0.4s, so scanning every
# controller is the gate's tallest pole AND the one part that grows with the
# workload count.
#
# But a kubesec score depends ONLY on the security posture — the pod- and
# container-level securityContext, resources, hostPath/host-namespace use, and the
# ServiceAccount-token settings — never on the image, name, ports or env. So many
# controllers share a byte-identical posture and therefore an identical score.
# Fingerprint each controller by exactly those fields, and scan ONE representative
# per DISTINCT posture: the floor is still proven for every posture the library
# emits, but the scan count is bounded by the (small, finite) number of security
# relaxations rather than by the number of workloads. The full per-controller scan
# stays available via KUBESEC_ALL=1 for a belt-and-suspenders sweep.
echo "== kubesec (security score, one scan per distinct posture) =="
export THRESHOLD=6

# The kubesec-relevant fields of a controller, as a canonical fingerprint. A pod
# lives directly under .spec; a CronJob nests it under jobTemplate; the rest under
# .spec.template.
fingerprint='
  def podspec:
    if .kind == "CronJob" then .spec.jobTemplate.spec.template.spec
    elif .kind == "Pod" then .spec
    else .spec.template.spec end;
  podspec | {
    psc: .securityContext,
    hostNetwork: .hostNetwork, hostPID: .hostPID, hostIPC: .hostIPC, hostUsers: .hostUsers,
    sa: (.serviceAccountName != null), automount: .automountServiceAccountToken,
    hostpath: ([.volumes[]? | select(has("hostPath"))] | length),
    containers: [.containers[] | { sc: .securityContext, res: .resources }],
    init: [.initContainers[]? | { sc: .securityContext, res: .resources }]
  }'

# Emit one line per scannable controller: <source-key> <TAB> <fingerprint b64> <TAB>
# <manifest b64>. base64 keeps the JSON safe across the line delimiter. The source
# key drives the escape-hatch exemptions below.
jq -rc "
  to_entries[] | .key as \$k
  | (.value.items[]? | select(.kind == \"Deployment\" or .kind == \"DaemonSet\" or .kind == \"CronJob\" or .kind == \"Pod\"))
  | [\$k, (($fingerprint) | @base64), (@base64)] | @tsv
" "$all" > "$workdir/controllers.tsv"

# Group by posture, honouring the exemptions (the escape-hatch demos and spegel,
# which is node infrastructure that cannot reach the floor with hostPath present).
# For each distinct posture keep one representative manifest and count its members.
declare -A rep_b64 members
while IFS="$(printf '\t')" read -r key fp mb64; do
  case "$key" in
    examples-legacy | examples-cron) continue ;;
    workloads-spegel-*) continue ;;
  esac
  if [ "${KUBESEC_ALL:-}" = "1" ]; then fp="$key-$fp"; fi  # full sweep: never merge
  members["$fp"]="${members["$fp"]:-0}"
  members["$fp"]=$(( members["$fp"] + 1 ))
  if [ -z "${rep_b64["$fp"]:-}" ]; then rep_b64["$fp"]="$key"$'\t'"$mb64"; fi
done < "$workdir/controllers.tsv"

echo "scanning $(printf '%s\n' "${!rep_b64[@]}" | wc -l) distinct posture(s) across $(wc -l < "$workdir/controllers.tsv") controller(s)"

scan_one() { # <key> <manifest-b64> <member-count>
  local key="$1" mb64="$2" n="$3" f score
  f="$(mktemp)"; printf '%s' "$mb64" | base64 -d > "$f"
  score="$(kubesec scan "$f" | jq -r '.[0].score')"
  rm -f "$f"
  if [ "$score" -lt "$THRESHOLD" ]; then
    echo "  FAIL ${key} scored ${score} (< ${THRESHOLD}) — posture shared by ${n} controller(s)" >&2
    return 1
  fi
  echo "  ok   ${key} scored ${score} (posture shared by ${n} controller(s))"
}
export -f scan_one
export THRESHOLD

# Scan the representatives in parallel across cores. Each line is
# <key><TAB><manifest-b64><TAB><count>; the child splits it and scans.
fail=0
# shellcheck disable=SC2016
if ! for fp in "${!rep_b64[@]}"; do
  key="${rep_b64["$fp"]%%$'\t'*}"
  mb64="${rep_b64["$fp"]#*$'\t'}"
  printf '%s\t%s\t%s\n' "$key" "$mb64" "${members["$fp"]}"
done | xargs -P"$(nproc)" -d '\n' -I{} bash -c 'IFS=$(printf "\t") read -r k m n <<<"$1"; scan_one "$k" "$m" "$n"' _ {}; then
  fail=1
fi
if [ "$fail" != "0" ]; then
  echo "kubesec: a hardened controller scored below $THRESHOLD" >&2
  exit 1
fi

echo "all security checks passed"
