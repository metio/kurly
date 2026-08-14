<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# hypermind

[Hypermind](https://github.com/lklynet/hypermind) — a peer-to-peer deployment counter and
ephemeral chat. Every instance joins a Hyperswarm DHT, finds the others running the same
image, and shows how many there are. Upstream describes it as "the high-availability
solution to a problem that doesn't exist", and this recipe takes it at its word.

A plain composable `kurly.http` workload: no database, no volume, no external service.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local hypermind = import 'github.com/metio/kurly/workloads/hypermind/server.libsonnet';

kurly.list(
  hypermind()
  + kurly.expose.gateway('hypermind.example.com', parent='public')
)
```

## It dials strangers on the public internet

Finding peers means outbound connections to a distributed hash table. In a cluster with a
default-deny egress policy it has nothing to count; in a cluster without one it holds
connections to peers nobody vetted. Both are the honest outcome of what this is, not a
misconfiguration.

## Replicas are peers, not capacity

Two replicas do not serve twice the traffic — they find each other and the count goes up
by one. Nothing is persisted: messages last as long as a peer is connected, and a restart
starts over.
