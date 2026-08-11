#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the k8up workload. Every stage renders a CUSTOM RESOURCE that K8up's own
# operator reconciles, so none of them boots a pod of its own: what is proven here
# is that the operator's schema accepts what we render, by a server-side dry-run
# against the real CRDs. The round trip — a backup actually taken and restored — is
# the deep scenario's job, which stands up the operator and an object store.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

# renovate: datasource=github-releases depName=k8up-io/k8up
K8UP_VERSION="4.8.0"
crd="https://github.com/k8up-io/k8up/releases/download/k8up-${K8UP_VERSION}/k8up-crd.yaml"

ns="$(kurly::namespace_unique kurly-k8up)"
kurly::validate_cr "$ns" workloads/k8up/backup.libsonnet "$crd"
kurly::validate_cr "$ns" workloads/k8up/restore.libsonnet
kurly::validate_cr "$ns" workloads/k8up/schedule.libsonnet
