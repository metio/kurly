# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Single-layer OCI image of ONE workload's Jsonnet source, laid out like a jb
# vendor/ tree (/github.com/metio/kurly/workloads/<name>/…) — the same shape and
# contract as the library image: a Flux OCIRepository source (selector-less,
# single-layer) that JaaS extracts to the vendor tree, imports a stage from, and
# renders with the consumer's parameters. k8s-libsonnet and the kurly library are
# supplied separately as their own JsonnetLibraries, so only the workload's own
# directory ships here.
#
# Shared across every workload: WORKLOAD names the directory to pack. One
# directory is one COPY, so the image is a single layer without a staging stage.
# The release version is written into the workload's version.txt (which its
# stages read with importstr) before the build, so the source is already
# stamped — nothing is rewritten here.
FROM scratch
ARG WORKLOAD
COPY workloads/${WORKLOAD} /github.com/metio/kurly/workloads/${WORKLOAD}
