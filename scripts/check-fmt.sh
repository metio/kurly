# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# jsonnetfmt in check mode across every source (empty output == clean). The
# file set lives here, so CI and a local run format-check the same files.
jsonnetfmt --test ./*.libsonnet ./examples/*.jsonnet ./workloads/*/*.jsonnet ./tests/*.jsonnet
