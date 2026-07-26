#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e (fast schema check) for the tempo workload: install the Tempo operator CRDs and
# validate the rendered TempoStack against the operator schema with a server-side
# dry-run — a quick "is this version's manifest broken" signal. Standing up the
# real cluster the operator reconciles is the deeper tier that comes later.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

# renovate: datasource=github-releases depName=grafana/tempo-operator
TEMPO_VERSION="0.15.0"

kurly::validate_cr kurly-tempo workloads/tempo/server.libsonnet \
  "https://raw.githubusercontent.com/grafana/tempo-operator/v${TEMPO_VERSION}/config/crd/bases/tempo.grafana.com_tempostacks.yaml"
