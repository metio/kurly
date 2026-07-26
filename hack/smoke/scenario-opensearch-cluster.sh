#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e (fast schema check) for the opensearch-cluster workload: install the OpenSearch operator CRDs and
# validate the rendered OpenSearchCluster against the operator schema with a server-side
# dry-run — a quick "is this version's manifest broken" signal. Standing up the
# real cluster the operator reconciles is the deeper tier that comes later.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

# renovate: datasource=github-releases depName=opensearch-project/opensearch-k8s-operator
OPENSEARCH_CLUSTER_VERSION="2.7.0"

kurly::validate_cr kurly-opensearch-cluster workloads/opensearch-cluster/cluster.libsonnet \
  "https://raw.githubusercontent.com/opensearch-project/opensearch-k8s-operator/v${OPENSEARCH_CLUSTER_VERSION}/opensearch-operator/config/crd/bases/opensearch.opster.io_opensearchclusters.yaml"
