# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Render every example and workload and validate each manifest against the
# Kubernetes / CRD schemas. The vendored library is needed to render, so
# install it first; hack/validate-examples.sh does the rendering + kubeconform.
jb install

# Resolve kurly's canonical import path (github.com/metio/kurly/...) locally by
# symlinking the repo into the vendor tree, so workloads — which import kurly by
# that path, exactly as JaaS resolves it in-cluster — render the same way here.
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

hack/validate-examples.sh
