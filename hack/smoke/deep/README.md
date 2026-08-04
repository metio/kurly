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

The **deep tier** delivers a workload the way a consumer does: its source image is
built and pushed, Flux pulls it (`OCIRepository`), JaaS renders it
(`JsonnetSnippet`), and stageset-controller applies it (`StageSet`) until every
controller rolls out. That walk is generic — `kurly::deep` in `hack/smoke/lib.sh`
drives it from the catalog for any workload — so it needs no per-workload file.
`hack/smoke/deep-run.sh` walks the whole fleet with it and records each green
workload, with the date, in `catalog/delivered-verified.libsonnet` — the evidence
behind the catalog's `maturity.delivered`, an axis of its own rather than a rung
on the tier ladder:

```shell
nix develop --command bash hack/smoke/deep-run.sh            # the whole fleet
nix develop --command bash hack/smoke/deep-run.sh tik valkey # just these
```

The walk is resumable and writes the ledger after each workload, so a run stopped
halfway keeps everything it proved. A workload whose stages render only a custom
resource has no controller to roll out and cannot reach the tier.

The scenarios in this directory are hand-written on top of that, and each
proves a seam the generic walk cannot see — a migration ladder delivered through
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

One of them proves an **axis** rather than a workload, and it is green. `mesh-istio.sh` stands up
a real Istio control plane and checks what rendering cannot: that a pod composed
with `kurly.mesh.istio()` comes up with a sidecar in a namespace carrying no
injection label, that the same app carrying the annotation form instead comes up
without one, that a client with no sidecar is refused, that a client with one
gets through — and, as the control, that removing the `PeerAuthentication` and
changing nothing else lets the refused request succeed. Without that last step
the refusal proves only that a request failed, which it can do for a hundred
reasons that have nothing to do with mTLS.

`mesh-linkerd.sh` is the same five questions for the other mesh, which is the
point: the two recipes promise a consumer the same thing while emitting almost
nothing in common, so the evidence has to be the same shape or the promise is
not tested. Its steps 1 and 2 are the mirror image of Istio's — Linkerd's
injector reads an annotation and ignores the label, Istio's the reverse.

Both scenarios run their POSITIVE control first — a meshed client reaching the
workload — before asserting the refusal, because "the request failed" is the
weakest evidence in either file. An earlier ordering asserted the refusal first
and passed against a port nothing was listening on. Two more differences between
the meshes are pinned in comments there, having each cost a wrong verdict:
Linkerd exempts a pod's declared probe path from authentication by design, so
the scenarios probe a path the test does not request; and Linkerd refuses with a
403 where Istio closes the connection, so the reachability check reads the HTTP
status rather than curl's exit code.

`mesh-bsi.sh <mesh>` asks the follow-on question: what does the mesh cost at admission?
The catalogue's `bsi` is measured on what kurly RENDERS, and a meshed pod is not
that — the injector adds containers between the manifest and the pod, and those
containers are in bollwerk's scope. It deploys the same app meshed and bare,
re-submits each resulting pod as a dry-run CREATE so the policies warn to us
(the method `cr-bsi.sh` uses for operator-made pods), and reports the difference,
then repeats it with that mesh's CNI plugin installed and measures the node
agent that takes over the privileged work. Both meshes have the same problem and
the same escape.

They are not part of the per-workload walk, so a missing registry or an operator
that is slow to come up never blocks a workload's fast check. A workload a deep
scenario exercises still counts toward the `e2e` maturity tier.
