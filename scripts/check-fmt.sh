# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# jsonnetfmt in check mode across every source (empty output == clean). The
# file set lives here, so CI and a local run format-check the same files.
#
# An unmatched glob must expand to nothing rather than to its own pattern: no
# workload ships a .jsonnet today, and the literal pattern would reach jsonnetfmt
# as a filename and fail the gate.
shopt -s nullglob
jsonnetfmt --test ./*.libsonnet ./lib/*.libsonnet ./catalog/*.libsonnet ./catalog/*.jsonnet ./examples/*.jsonnet ./workloads/*/*.jsonnet ./tests/*.jsonnet
