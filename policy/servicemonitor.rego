# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# A cross-manifest invariant, so it runs over the COMBINED render rather than one
# object at a time: a ServiceMonitor scrapes a Service port BY NAME, and a name
# no selected Service exposes yields a monitor Prometheus wires up and never
# scrapes — clean YAML, zero metrics, discovered only when a dashboard stays
# empty. Checking it in the workload's own config could not see a port a consumer
# adds to the Service through the raw `+` escape; checking it here, over
# everything combined, honours that port because the rendered Service carries it.
#
# Run under its own namespace (conftest --combine --namespace combined) so the
# per-object invariants in kurly.rego, which read one manifest as `input`, are
# untouched — here `input` is the array of every rendered object.
package combined

import rego.v1

objects := [c.contents | some c in input]

services := [o | some o in objects; o.kind == "Service"]

service_monitors := [o | some o in objects; o.kind == "ServiceMonitor"]

# A ServiceMonitor selects a Service when the Service's labels carry every
# matchLabels pair — the same subset rule the apiserver applies.
selects(sm, svc) if {
	every key, val in sm.spec.selector.matchLabels {
		svc.metadata.labels[key] == val
	}
}

# The named port exists on some Service the monitor actually selects.
port_served(sm, name) if {
	some svc in services
	selects(sm, svc)
	some port in svc.spec.ports
	port.name == name
}

deny contains msg if {
	some sm in service_monitors
	some endpoint in sm.spec.endpoints
	not port_served(sm, endpoint.port)
	msg := sprintf("ServiceMonitor/%s scrapes port %q, which no Service it selects exposes — Prometheus would wire it up and never scrape it", [sm.metadata.name, endpoint.port])
}
