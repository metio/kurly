#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the volsync workload. Both stages render CUSTOM RESOURCES that VolSync's
# operator reconciles, so neither boots a pod of its own: what is proven here is
# that the operator's schema accepts what we render, by a server-side dry-run
# against the real CRDs. Actually moving a volume off the cluster and back is the
# deep scenario's job, which stands up the operator and an object store.
#
# VolSync publishes no CRD bundle to fetch — the definitions live in its chart — so
# they are rendered out of it and applied here, rather than passed to
# kurly::validate_cr as URLs.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

# renovate: datasource=helm depName=volsync registryUrl=https://backube.github.io/helm-charts/
VOLSYNC_VERSION="0.13.0"

echo "== install the VolSync CRDs ${VOLSYNC_VERSION} =="
helm repo add backube https://backube.github.io/helm-charts/ >/dev/null 2>&1 || true
helm repo update backube >/dev/null 2>&1 || true
# The chart TEMPLATES its CRDs rather than shipping a crds/ directory, so
# `helm show crds` prints nothing and only the rendered output carries them. The
# CustomResourceDefinition documents are selected out of it; applying the whole
# render would install the operator as well, which this check does not need.
helm template volsync backube/volsync --version "$VOLSYNC_VERSION" --include-crds \
  --namespace volsync-system \
  | yq 'select(.kind == "CustomResourceDefinition")' \
  | kubectl apply --server-side --force-conflicts --filename=- >/dev/null
kubectl wait --for=condition=Established --timeout=120s \
  crd/replicationsources.volsync.backube crd/replicationdestinations.volsync.backube >/dev/null
rm -rf "${HOME}/.kube/cache/discovery" 2>/dev/null || true

ns="$(kurly::namespace_unique kurly-volsync)"
kurly::validate_cr "$ns" workloads/volsync/backup.libsonnet
kurly::validate_cr "$ns" workloads/volsync/restore.libsonnet
