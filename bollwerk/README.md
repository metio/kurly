<!--
SPDX-FileCopyrightText: The Bollwerk Authors
SPDX-License-Identifier: Apache-2.0
-->

# Bollwerk

**BSI IT-Grundschutz hardening as native Kubernetes admission control.** Bollwerk
renders the *IG BvC Richtlinien* — the BSI IT-Grundschutz building blocks
**APP.4.4 (Kubernetes)** and **SYS.1.6 (Container)** — as
[`ValidatingAdmissionPolicy`](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
objects. No Kyverno, no Gatekeeper, no third-party admission engine: the checks
run in the API server's own CEL, so there is nothing extra to install, secure, or
keep alive on the admission path.

It complements kurly's workloads, which ship the `restricted` posture baked in:
Bollwerk enforces that same baseline at the gate, for everything applied to the
cluster.

## Source

Bollwerk is a Jsonnet rendering of the Kyverno `validate.cel` policies from
**<https://gitlab.opencode.de/ig-bvc/policy-entwicklung/richtlinien-umsetzung-kyverno>**
(Apache-2.0). Those policies already express their checks in CEL — the *same*
language `ValidatingAdmissionPolicy` uses — so the validation logic transfers
**verbatim**; only the wrapper changes (`match` → `matchConstraints`,
`validationFailureAction` → the binding's `validationActions`).

## Render and apply

```shell
# every policy + binding as a kind: List
jsonnet bollwerk/bollwerk.libsonnet -e '(import "bollwerk/bollwerk.libsonnet").list' \
  | kubectl apply -f -
```

Or import the library and pick what you need:

```jsonnet
local bollwerk = import 'bollwerk/bollwerk.libsonnet';

bollwerk.list                                          // all 23 policies + bindings
bollwerk.policies['015-disallow-privileged-containers'] // one [VAP, Binding] pair
```

The shared CEL building blocks (`podSpecVar`, `containersVar`, `workloadRules`)
and the `policy(id, name, opts)` constructor are exported too, so a cluster can
add its own house rules in the same shape.

### Allowed registries

Policy 004 restricts which registries an image may come from. The list is a hidden
field, defaulting to the public registries kurly's workloads ship from — override
it for your environment:

```jsonnet
(import 'bollwerk/bollwerk.libsonnet') { allowedRegistries:: ['registry.opencode.de'] }
```

## What's enforced

23 policies across the two building blocks — privileged containers, capabilities,
read-only root filesystem, non-root user/groups, privilege escalation, host
ports/namespaces, hostPath, seccomp/AppArmor/SELinux, probes, resource
requests/limits, image registries and the `:latest` tag, the default
ServiceAccount and token automount, Service `externalIPs`, and NetworkPolicy
remote-access ports. Each carries the source's BSI annotations
(`policies.opencode.de/bsi-requirement`, …).

## Three deliberate departures from the source

- **Pod-spec located by shape, not `object.kind`.** The source branches the
  pod-spec location on `object.kind`, which is unreliable under native VAP —
  built-in objects carry no TypeMeta in the CEL `object`. Bollwerk branches on the
  spec **shape** instead (`has(spec.jobTemplate)` → CronJob, `has(spec.template)`
  → controller, else a bare Pod), which is robust without Kyverno's behind-the-
  scenes population.
- **Policy 004 checks the image string, not `image.registry`.** The source selects
  `container.image.registry`, but under native VAP `container.image` is a plain
  string with no `.registry` field, so that selection does not compile. Bollwerk
  matches a fully-qualified image reference against the [allowed-registry
  list](#allowed-registries) by string prefix.
- **Policy 130 reinterpreted.** The source's `disallow-remote-access-ports` is a
  legacy Kyverno `anyPattern` (not CEL); Bollwerk renders its **intent** as CEL —
  no NetworkPolicy ingress rule may open SSH/Telnet/RDP/VNC (22/23/3389/5900).

**Not converted:** `XXX-require-unique-uid-per-workload` needs to compare against
*other* objects in the cluster, which `ValidatingAdmissionPolicy` cannot do (no
cross-object lookups). That one genuinely needs Kyverno or a parameterised
approach, and it is the source's draft (`XXX`) policy.

## Audit vs. enforce

Each policy carries the source's `validationFailureAction` on its binding —
`Audit` (report only, surfaced in the API server's audit log and metrics) or
`Deny` (block the request). Flip a binding's `validationActions` to roll a policy
from observe to enforce, or scope a binding with `matchResources.namespaceSelector`
to exempt system namespaces during rollout.

## Running kurly under bollwerk

Every kurly workload admits under bollwerk with its policies enforcing, out of the
box. The two that **block** a request — 015 (privileged containers) and 019 (the
`default` ServiceAccount) — are clean for every workload: kurly's `restricted`
posture is never privileged, and **every workload runs under a dedicated
ServiceAccount named after itself** (with its token unmounted unless the workload
actually reaches the apiserver), so nothing falls back to `default`. The
[e2e](../.github/workflows/e2e-bollwerk.yml) proves this against a real API server:
it installs these policies and applies the whole workload catalogue, asserting each
admits while a privileged pod and a default-ServiceAccount pod are denied.

> The dedicated ServiceAccount is emitted for **every** workload now, and every pod
> carries a `serviceAccountName`. If you had RBAC bound to the namespace `default`
> account for kurly pods, rebind it to the workload's own account.

The remaining policies ship as `Audit`. kurly already satisfies most of them
(read-only root filesystem, dropped capabilities, seccomp, no host
ports/namespaces, …). A few are **environment choices** a consumer makes before
promoting them to `Deny`:

- **004 (registries)** — set [`allowedRegistries`](#allowed-registries) to the
  registries you permit.
- **017 / 018 (UID/GID > 65535)** — BSI wants very high UIDs; kurly's storage
  workloads pin the UID their image expects (often `1000`). Raise it with
  `kurly.runAs` where the image tolerates an arbitrary UID.
- **001 (resource limits)** and **029 (probes)** — compose `kurly.resources` and a
  probe onto workloads that lack them (background workers carry neither by default).

## License

Apache-2.0 — Bollwerk is a derivative of the Apache-2.0 opencode.de policies, so it
keeps that license (distinct from kurly's 0BSD; see the SPDX headers).
