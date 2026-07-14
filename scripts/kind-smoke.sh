# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Applies kurly's rendered output to the current cluster (a kind cluster in CI)
# and waits for it to become Ready — proving the manifests kurly produces are
# not just schema-valid (that is check-security/kubeconform) but actually run.
#
# The tik workload is applied and awaited: a real, published image built for
# kurly's restricted profile — a PVC that binds WaitForFirstConsumer, a mounted
# ConfigMap, an optional signing-key Secret, a scratch emptyDir for its
# read-only root filesystem, a pinned non-root uid, and the Recreate strategy —
# whose board serves /tickets.edn. It is rendered from its composable stage app
# exactly as a consumer would (kurly.list of the app), with no exposure composed
# on (a route needs a Gateway controller this smoke does not run). The example
# workloads are NOT run here: they reference placeholder images
# (ghcr.io/example/...) or run stock images like nginx that need writable dirs
# the minimal examples don't grant under the read-only-rootfs default;
# check-examples renders and schema-checks them.
#
# Expects a reachable cluster (KUBECONFIG set); the workflow owns creating and
# tearing down the kind cluster, so this script runs against any cluster.

jb install
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

namespace="kurly-smoke"
kubectl create namespace "$namespace" --dry-run=client --output=yaml | kubectl apply --filename=-

echo "== apply the tik workload backend stage (PVC + ConfigMap + Deployment + Service) =="
jsonnet -J vendor -e "(import 'github.com/metio/kurly/main.libsonnet').list((import 'workloads/tik/backend.libsonnet')())" \
  | kubectl apply --namespace="$namespace" --filename=-

echo "== wait for the tik board to become Available =="
# tik's readiness probe IS GET /tickets.edn on the board port, so a successful
# rollout proves the board is serving — no separate probe needed.
if ! kubectl --namespace="$namespace" rollout status deployment/tik --timeout=300s; then
  echo "::group::tik diagnostics"
  kubectl --namespace="$namespace" get pods,persistentvolumeclaims
  kubectl --namespace="$namespace" describe deployment/tik
  kubectl --namespace="$namespace" logs deployment/tik --all-containers=true --tail=100 || true
  kubectl --namespace="$namespace" get events --sort-by=.lastTimestamp | tail -30
  echo "::endgroup::"
  exit 1
fi

echo "kurly's tik workload is Ready on a live cluster"
