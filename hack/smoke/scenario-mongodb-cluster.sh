#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e (fast schema check) for the mongodb-cluster workload: install the MongoDB Community operator CRDs and
# validate the rendered MongoDBCommunity against the operator schema with a server-side
# dry-run — a quick "is this version's manifest broken" signal. Standing up the
# real cluster the operator reconciles is the deeper tier that comes later.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

# renovate: datasource=github-releases depName=mongodb/mongodb-kubernetes-operator
MONGODB_CLUSTER_VERSION="0.12.0"

kurly::validate_cr kurly-mongodb-cluster workloads/mongodb-cluster/cluster.libsonnet \
  "https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/v${MONGODB_CLUSTER_VERSION}/config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml"
