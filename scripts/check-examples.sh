# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Render every example and workload and validate each manifest against the
# Kubernetes / CRD schemas. The vendored library is needed to render, so
# install it first; hack/validate-examples.sh does the rendering + kubeconform.
jb install
hack/validate-examples.sh
