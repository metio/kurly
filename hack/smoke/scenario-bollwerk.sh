#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Bollwerk conformance e2e: install the bollwerk ValidatingAdmissionPolicies (as
# shipped) into a kind cluster, then prove that every pod-bearing kurly workload
# ADMITS under them, while a privileged pod and a default-ServiceAccount pod are
# DENIED. Admission — not scheduling — is what a VAP evaluates, and a VAP fires on
# a server-side dry-run, so this checks the whole workload catalogue against a real
# apiserver in seconds without standing up a single operator or image.
#
# "As shipped" enforces bollwerk's two Deny policies (015 privileged, 019 default
# ServiceAccount); the rest are Audit and never block. That is exactly the claim
# under test: kurly runs with bollwerk installed.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hack/smoke/lib.sh
source "${here}/lib.sh"

kurly::vendor

echo "== install the bollwerk policies =="
jsonnet -J vendor -e 'local b = import "bollwerk/bollwerk.libsonnet"; b.list' \
  | kubectl apply --filename=-

ns=bollwerk-e2e
kurly::namespace "$ns"

# A ValidatingAdmissionPolicyBinding is not enforced the instant its object lands;
# the apiserver compiles and activates it asynchronously. Poll a control that MUST
# be denied once 019 is live — a pod left on the `default` ServiceAccount — and
# only proceed once the deny actually fires, so the positive checks below cannot
# pass merely because enforcement had not started yet.
echo "== wait for enforcement to activate =="
deadline=$((SECONDS + 120))
until ! kubectl --namespace="$ns" apply --dry-run=server --filename=- >/dev/null 2>&1 <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: probe-default-sa
spec:
  containers:
    - name: c
      image: docker.io/library/busybox:1.37
YAML
do
  [ "$SECONDS" -lt "$deadline" ] || {
    echo "::error::bollwerk enforcement never activated within the timeout"
    exit 1
  }
  sleep 3
done
echo "enforcement is active (a default-ServiceAccount pod is denied)."

# The kinds bollwerk's workload rules match. A workload that renders only custom
# resources (a CNPG Cluster, a Grafana, a LokiStack) has nothing bollwerk governs,
# so it drops out here rather than needing its operator's CRDs installed.
governed='Pod|Deployment|DaemonSet|StatefulSet|Job|CronJob|Service|ServiceAccount|PersistentVolumeClaim|NetworkPolicy'

fails=0
tested=0
echo "== every governed workload must admit =="
for stage in workloads/*/*.libsonnet; do
  path="github.com/metio/kurly/${stage}"
  rendered="$(jsonnet -J vendor -e \
    "local k = import 'github.com/metio/kurly/main.libsonnet'; k.list((import '${path}')())" 2>/dev/null)" || {
    echo "  skip (render needs params) ${stage}"
    continue
  }
  subset="$(jq -c \
    "{apiVersion: \"v1\", kind: \"List\", items: [.items[] | select(.kind | test(\"^(${governed})\$\"))]}" \
    <<<"$rendered")"
  [ "$(jq '.items | length' <<<"$subset")" -gt 0 ] || {
    echo "  skip (no governed kinds) ${stage}"
    continue
  }
  tested=$((tested + 1))
  if err="$(kubectl --namespace="$ns" apply --server-side --force-conflicts \
    --dry-run=server --filename=- <<<"$subset" 2>&1)"; then
    echo "  ADMIT ${stage}"
  else
    echo "::error::DENIED ${stage}"
    grep -iE 'denied|policy|ValidatingAdmission' <<<"$err" || tail -3 <<<"$err"
    fails=$((fails + 1))
  fi
done

echo "== negative controls: enforcement must actually deny =="
# A privileged container trips 015 (Deny). It carries a non-default ServiceAccount
# so 019 is not the reason it is rejected.
if kubectl --namespace="$ns" apply --dry-run=server --filename=- >/dev/null 2>&1 <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: probe-privileged
spec:
  serviceAccountName: probe
  containers:
    - name: c
      image: docker.io/library/busybox:1.37
      securityContext:
        privileged: true
YAML
then
  echo "::error::a privileged pod was admitted — policy 015 is not enforcing"
  fails=$((fails + 1))
else
  echo "  DENIED a privileged pod (015)"
fi

if [ "$fails" -ne 0 ]; then
  echo "::error::${fails} conformance check(s) failed"
  kurly::diagnose "$ns"
  exit 1
fi
echo "== all ${tested} governed workloads admit under bollwerk; controls denied =="
