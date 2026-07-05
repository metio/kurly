# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Single-layer OCI image carrying the kurly library as Jsonnet source, laid out
# like a jb vendor/ tree (/github.com/metio/kurly/…) so the same import works
# locally (`jsonnet -J vendor`) and in-cluster. k8s-libsonnet is deliberately
# NOT bundled — it is supplied at render time as its own JsonnetLibrary (the
# JOI k8s-libsonnet image), the same way any snippet's libraries are. The lone
# COPY is the only layer, so the image works as both a Flux OCIRepository
# source and an image-volume mount — the same contract the JOI images satisfy.
FROM scratch
COPY *.libsonnet /github.com/metio/kurly/
