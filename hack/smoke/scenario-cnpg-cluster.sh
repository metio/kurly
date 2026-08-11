#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the cnpg-cluster workload. This renders a CUSTOM RESOURCE, so there is
# nothing to boot: kurly's features do not apply to it and no pod is created by the
# manifest itself. What can be proven is that the operator's own schema accepts
# what we render — a server-side dry-run against the real CRD, which catches a
# field that has been renamed or removed upstream. That is why this scenario is
# hand-written: the CRD URL is not something the catalogue carries.
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

ns="$(kurly::namespace_unique kurly-cnpg-cluster)"
kurly::validate_cr "$ns" workloads/cnpg-cluster/cluster.libsonnet
