#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the cnpg-image-catalog workload: both stages are CUSTOM RESOURCES, so
# each is validated against the operator's own schema by a server-side dry-run
# rather than booted. The two differ in scope — a cluster-wide catalogue and a
# namespaced one — and both are checked, because a field accepted by one kind is
# not evidence about the other.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

# renovate: datasource=github-releases depName=cloudnative-pg/cloudnative-pg
CNPG_VERSION="1.30.0"

# The published manifest is the whole operator, not a CRD bundle, so it is applied
# here rather than handed to kurly::validate_cr: that helper waits for everything
# it applied to become Established, which a Deployment never does. The CRDs are
# waited for by name instead, and the validation below then runs against them.
kubectl apply --server-side --force-conflicts \
  --filename="https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v${CNPG_VERSION}/cnpg-${CNPG_VERSION}.yaml" >/dev/null
kubectl wait --for=condition=Established --timeout=120s \
  crd/clusters.postgresql.cnpg.io crd/imagecatalogs.postgresql.cnpg.io \
  crd/clusterimagecatalogs.postgresql.cnpg.io >/dev/null
rm -rf "${HOME}/.kube/cache/discovery" 2>/dev/null || true

ns="$(kurly::namespace_unique kurly-cnpg-image-catalog)"
kurly::validate_cr "$ns" workloads/cnpg-image-catalog/cluster.libsonnet
kurly::validate_cr "$ns" workloads/cnpg-image-catalog/namespaced.libsonnet
