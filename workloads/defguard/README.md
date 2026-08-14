<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# defguard

[defguard](https://github.com/DefGuard/defguard) — identity and access management built
around WireGuard. It holds the user accounts, the MFA enrolment, an OpenID Connect
provider, and the peer configuration that its gateways enforce.

This carries **core**, the control plane: a plain composable `kurly.http` workload backed
by an external PostgreSQL, holding no state of its own.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local defguard = import 'github.com/metio/kurly/workloads/defguard/core.libsonnet';

kurly.list(
  defguard(url='https://vpn.example.com')
  + kurly.expose.gateway('vpn.example.com', parent='public')
)
```

## Core is not the VPN

Core hands each gateway its peer list; the gateway that actually carries WireGuard
traffic needs `NET_ADMIN` and the node's own network, and is a separate deployment
decision from this one. Running core alone gives you the directory and the admin
interface with no tunnel behind them.

## Secure cookies and plain HTTP

The application marks its session cookies `Secure`, so a browser reaching it over `http://`
discards them and the login never completes. `cookieInsecure` relaxes that for a
deployment terminating TLS somewhere the application cannot see. It is the wrong answer
for anything on a network you do not fully control.

## Licence

The core is AGPL-3.0. Enterprise features live in the same repository under a separate
licence, and the published image is one build — which of the two applies depends on which
features are switched on.
