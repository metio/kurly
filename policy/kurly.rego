# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# kurly's own invariants, enforced on the RENDERED manifests with conftest
# (OPA/Rego). Rego reads structured data, so it runs on the JSON jsonnet emits —
# a policy layer the general best-practice tools can't express. These rules hold
# for EVERY kurly workload regardless of which features are composed (the
# security hatches relax pod-level settings, but never these structural
# guarantees), so the suite stays green by construction and any violation is a
# real regression in the recipes.
package main

import rego.v1

# The pod-bearing kinds and where their containers live.
containers(obj) := obj.spec.template.spec.containers if obj.kind in {"Deployment", "DaemonSet"}

containers(obj) := obj.spec.jobTemplate.spec.template.spec.containers if obj.kind == "CronJob"

# The kinds kurly stamps with its managed-by label.
managed := {"Deployment", "Service", "CronJob", "DaemonSet", "Ingress", "PersistentVolumeClaim", "ConfigMap", "HTTPRoute", "Gateway", "ListenerSet"}

# Every kurly-owned object carries the managed-by label, so an operator can tell
# what kurly produced from what they hand-wrote.
deny contains msg if {
	input.kind in managed
	object.get(input.metadata, ["labels", "app.kubernetes.io/managed-by"], "") != "kurly"
	msg := sprintf("%s/%s is missing the app.kubernetes.io/managed-by=kurly label", [input.kind, input.metadata.name])
}

# Images are pinned to a tag — never :latest, never untagged — so a rollout
# deploys a known, reproducible artifact.
deny contains msg if {
	some container in containers(input)
	endswith(container.image, ":latest")
	msg := sprintf("container %q uses the :latest tag — pin a specific tag or digest", [container.name])
}

deny contains msg if {
	some container in containers(input)
	not contains(container.image, ":")
	not contains(container.image, "@")
	msg := sprintf("container %q image %q is untagged — pin a specific tag or digest", [container.name, container.image])
}

# Selector stability: a Deployment/DaemonSet matchLabels carries only the stable
# identity keys. User labels (from kurly.labels) reach metadata and the pod
# template but must never leak into an immutable selector, or a later
# `kubectl apply` that changes a label fails on the immutable field.
stable_selector_keys := {"name", "app.kubernetes.io/name"}

deny contains msg if {
	input.kind in {"Deployment", "DaemonSet"}
	some key in object.keys(input.spec.selector.matchLabels)
	not key in stable_selector_keys
	msg := sprintf("%s/%s selector matchLabels has the volatile key %q — selectors must stay stable", [input.kind, input.metadata.name, key])
}

# A mounted volume and its container mount agree on the volume name, so a rename
# can never leave a mount dangling.
deny contains msg if {
	input.kind in {"Deployment", "DaemonSet"}
	volume_names := {v.name | some v in object.get(input.spec.template.spec, "volumes", [])}
	some container in input.spec.template.spec.containers
	some mount in object.get(container, "volumeMounts", [])
	not mount.name in volume_names
	msg := sprintf("%s/%s container %q mounts %q, which has no matching volume", [input.kind, input.metadata.name, container.name, mount.name])
}
