# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Single-layer OCI image carrying the kurly library as Jsonnet source, laid out
# like a jb vendor/ tree (/github.com/metio/kurly/…) so the same import works
# locally (`jsonnet -J vendor`) and in-cluster. k8s-libsonnet is deliberately
# NOT bundled — it is supplied at render time as its own JsonnetLibrary (the
# JOI k8s-libsonnet image), the same way any snippet's libraries are.
#
# The entry point `main.libsonnet` imports the recipe modules under `lib/`, so
# BOTH must reach the vendor tree at their real paths — an image with only
# `main.libsonnet` fails the first `import './lib/…'` a consumer triggers. Two
# COPYs would be two layers, and a single layer is the contract a selector-less
# Flux OCIRepository and JaaS's vendor-tree search both rely on. A staging stage
# collapses both into one: its own layers are discarded, and the final scratch
# image carries a single COPY layer holding the whole tree.
FROM scratch AS src
COPY main.libsonnet /github.com/metio/kurly/main.libsonnet
COPY lib /github.com/metio/kurly/lib

FROM scratch
COPY --from=src / /
