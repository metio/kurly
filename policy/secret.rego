# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# kurly never creates a Secret. A workload names the Secret it needs and leaves
# the authoring to someone — or something — else: the cluster operator, External
# Secrets Operator, SOPS, a sealed secret, a hand-applied one. So no recipe
# renders a Secret at all, empty or not. This invariant makes that a structural
# guarantee: any Secret kurly emits fails the gate. It holds by construction —
# every workload references Secrets by name (imagePullSecrets, secretMount, a
# LokiStack's storage Secret) and authors none — so a violation is a real
# regression. Referencing by name (never authoring) is also what lets a consumer
# fill ANY named Secret from their own secrets store: point kurly.externalSecret
# at the same name and ESO reconciles it in (see main.libsonnet).
package main

import rego.v1

deny contains msg if {
	input.kind == "Secret"
	msg := sprintf("Secret/%s is rendered by kurly — kurly never creates Secrets; reference an existing Secret by name and let the cluster operator or External Secrets Operator author it (see kurly.externalSecret)", [object.get(input.metadata, "name", "<unnamed>")])
}
