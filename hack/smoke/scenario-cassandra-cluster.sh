#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e (fast schema check) for the cassandra-cluster workload: install the cass-operator CRDs and
# validate the rendered CassandraDatacenter against the operator schema with a server-side
# dry-run — a quick "is this version's manifest broken" signal. Standing up the
# real cluster the operator reconciles is the deeper tier that comes later.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

# renovate: datasource=github-releases depName=k8ssandra/cass-operator
CASSANDRA_CLUSTER_VERSION="1.31.0"

kurly::validate_cr kurly-cassandra-cluster workloads/cassandra-cluster/cluster.libsonnet \
  "https://raw.githubusercontent.com/k8ssandra/cass-operator/v${CASSANDRA_CLUSTER_VERSION}/config/crd/bases/cassandra.datastax.com_cassandradatacenters.yaml"
