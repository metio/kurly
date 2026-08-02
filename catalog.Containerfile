# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The catalog as its own artifact: FROM scratch with the generated catalog.json
# at the root, so a consumer pins it by digest and copies it out of the image
# (COPY --from) the way it pins any other. Single layer, matching the library and
# workload source images.
#
# It ships the GENERATED file rather than the jsonnet that produces it: a
# consumer reads facts about the catalogue, and reading them must not require a
# jsonnet toolchain or the k8s-libsonnet the library renders against.
FROM scratch
COPY catalog/catalog.json /catalog.json
# Matching the library image: a scratch base inherits no user, and USER is
# metadata rather than a layer, so the single-layer contract above is unaffected.
USER 65532:65532
