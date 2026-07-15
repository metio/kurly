// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The single pin of the k8s-libsonnet API version every kurly module builds
// against. Bumping the directory here adopts a newer Kubernetes API surface
// for the whole library.
import 'github.com/jsonnet-libs/k8s-libsonnet/1.35/main.libsonnet'
