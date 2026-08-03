#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The operators cr-bsi.sh needs, installed on a throwaway cluster.
#
# Measuring what a CUSTOM-RESOURCE stage really runs means letting its operator
# turn the CR into pods, so the operator has to be here. This installs the ones
# that install cleanly and reports the ones that do not, because "the operator
# would not run" is a reason a stage goes unmeasured and belongs in the log
# rather than in a shrug.
#
# cert-manager goes first and is not optional: cass-operator waits on a webhook
# certificate, and tempo-operator rotates its own — without it they sit in
# ContainerCreating for hours giving no reason a caller would recognise.
#
# The versions here are the ones the fast-tier scenarios pin, so a stage is
# judged against the operator it is otherwise tested with. Renovate does not see
# them (they are strings in a script), which is the same footing scenario-*.sh
# is on.
set -uo pipefail

cd "$(dirname "$0")/../../.." || exit 1

CERT_MANAGER_VERSION="v1.19.1"
PROMETHEUS_OPERATOR_VERSION="v0.93.0"
CNPG_VERSION="1.30.0"
K8UP_CHART_VERSION="4.10.0"
TEMPO_OPERATOR_VERSION="v0.21.0"
VOLSYNC_VERSION="0.13.0"

ok() { echo "   ok"; }
no() { echo "::warning::${1} did not install — stages needing it stay unmeasured"; }

echo "== cert-manager ${CERT_MANAGER_VERSION} =="
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml" >/dev/null 2>&1
for d in cert-manager cert-manager-webhook cert-manager-cainjector; do
  kubectl -n cert-manager rollout status "deploy/${d}" --timeout=300s >/dev/null 2>&1 || no "cert-manager"
done
ok

echo "== prometheus-operator ${PROMETHEUS_OPERATOR_VERSION} (Prometheus, Alertmanager, ThanosRuler) =="
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/prometheus-operator/prometheus-operator/releases/download/${PROMETHEUS_OPERATOR_VERSION}/bundle.yaml" >/dev/null 2>&1
if kubectl -n default rollout status deploy/prometheus-operator --timeout=300s >/dev/null 2>&1; then ok; else no "prometheus-operator"; fi

echo "== CloudNativePG ${CNPG_VERSION} =="
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v${CNPG_VERSION}/cnpg-${CNPG_VERSION}.yaml" >/dev/null 2>&1
if kubectl -n cnpg-system rollout status deploy/cnpg-controller-manager --timeout=300s >/dev/null 2>&1; then ok; else no "cloudnative-pg"; fi

echo "== k8up ${K8UP_CHART_VERSION} =="
# The chart owns its CRDs. Applying them separately first leaves helm unable to
# take field ownership and every install then fails on a conflict.
helm repo add k8up-io https://k8up-io.github.io/k8up >/dev/null 2>&1
helm repo update >/dev/null 2>&1
if helm upgrade --install k8up k8up-io/k8up --version "${K8UP_CHART_VERSION}" \
  --namespace k8up-system --create-namespace --wait --timeout 5m >/dev/null 2>&1; then ok; else no "k8up"; fi

echo "== VolSync ${VOLSYNC_VERSION} =="
helm repo add backube https://backube.github.io/helm-charts/ >/dev/null 2>&1
helm repo update >/dev/null 2>&1
if helm upgrade --install volsync backube/volsync --version "${VOLSYNC_VERSION}" \
  --namespace volsync-system --create-namespace --wait --timeout 5m >/dev/null 2>&1; then ok; else no "volsync"; fi

echo "== tempo-operator ${TEMPO_OPERATOR_VERSION} =="
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/grafana/tempo-operator/releases/download/${TEMPO_OPERATOR_VERSION}/tempo-operator.yaml" >/dev/null 2>&1
if kubectl -n tempo-operator-system rollout status deploy/tempo-operator-controller --timeout=300s >/dev/null 2>&1; then ok; else no "tempo-operator"; fi

echo "== mysql-operator =="
kubectl apply --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/mysql/mysql-operator/trunk/deploy/deploy-crds.yaml" >/dev/null 2>&1
kubectl apply --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/mysql/mysql-operator/trunk/deploy/deploy-operator.yaml" >/dev/null 2>&1
if kubectl -n mysql-operator rollout status deploy/mysql-operator --timeout=300s >/dev/null 2>&1; then ok; else no "mysql-operator"; fi

# NOT INSTALLED, and each for a reason worth stating rather than retrying:
#
#   opensearch-operator  its manifest pulls
#       gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0, which no longer exists in
#       that registry. Nothing on this side fixes that.
#   loki-operator        needs the development overlay, a pinned image and three
#       feature gates turned off; hack/smoke/scenario-loki.sh carries that recipe
#       and is the place to run it from.
#   cass-operator        installs, then waits on a webhook certificate that never
#       arrives even with cert-manager present.
echo "== installed =="
kubectl get pods -A 2>/dev/null |
  grep -iE "cert-manager|prometheus-operator|cnpg|k8up|volsync|tempo-operator|mysql-operator" |
  awk '{print "   " $1 " " $2 " " $4}'
