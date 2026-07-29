<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# Deep e2e scenarios

The e2e checks are layered.

The **fast tier** is one generated scenario per catalogued workload,
`hack/smoke/scenario-<id>.sh`: render the stage's defaults the way a consumer
would, apply it to a small kind cluster, and wait for every controller to become
healthy (a custom-resource stage is server-side dry-run against the real operator
schema instead). It answers one question in seconds — *does this version's
manifest still run?* — which is the safety net the zero-touch Renovate policy
needs. `hack/smoke/e2e-run.sh` walks it for the workloads a pull request changed.

The scenarios in this directory are the **deep tier**: hand-written, and each
proves a seam the fast tier cannot see — a migration ladder delivered through
Flux → JaaS → stageset-controller, a CNPG cluster backing up into a SeaweedFS S3
gateway, a distributed SeaweedFS topology.

Two of them prove a **restore**, which is the half of a backup that matters:
`volsync-restore.sh` and `k8up-restore.sh` each write a known file into a
PersistentVolume, back it up to a SeaweedFS S3 gateway through the workload's
own recipe, **destroy the volume**, restore it, and read the file back. The
assertion is the file's contents — the only evidence that survives the volume it
came from. A scenario asserting that a backup job exited zero would prove bytes
left, not that they can come back. They stand up more infrastructure (a
registry, operators, the delivery stack), take minutes rather than seconds, and
are run deliberately:

```shell
nix develop --command bash hack/smoke/deep/tik-stageset.sh
```

They are not part of the per-workload walk, so a missing registry or an operator
that is slow to come up never blocks a workload's fast check. A workload a deep
scenario exercises still counts toward the `e2e` maturity tier.
