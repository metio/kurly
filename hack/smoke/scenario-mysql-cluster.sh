#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e (fast schema check) for the mysql-cluster workload: install the MySQL operator CRDs and
# validate the rendered InnoDBCluster against the operator schema with a server-side
# dry-run — a quick "is this version's manifest broken" signal. Standing up the
# real cluster the operator reconciles is the deeper tier that comes later.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

# renovate: datasource=github-tags depName=mysql/mysql-operator
MYSQL_CLUSTER_VERSION="9.1.0-2.2.3"

kurly::validate_cr kurly-mysql-cluster workloads/mysql-cluster/cluster.libsonnet \
  "https://raw.githubusercontent.com/mysql/mysql-operator/${MYSQL_CLUSTER_VERSION}/deploy/deploy-crds.yaml"
