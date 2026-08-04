<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# Adding a workload

The steps that turn "this software looks useful" into a catalogued, released
workload. Written down because most of it was previously spread across
`CLAUDE.md`, a dozen gates, and things learned by booting the whole catalogue
and watching what broke.

**This file is the HOW. The state of any particular candidate lives in tik**, as
the `kurly-workload` process in the metio store — one ticket per candidate,
stages derived from evidence rather than ticked off. The two are complementary
and deliberately not duplicated: tik records what is *true* about a workload and
regresses when that stops being true; this file explains how to *make* it true.

```shell
tik new kurly-workload --title "carry <name>"
tik explain <id>          # what evidence is missing, and who can act
tik probe <id>            # re-derive from the catalogue, the ledgers and git
```

Each stage's runbook (`kb/runbooks/kurly-workload-<stage>.md` in the store)
points back at the section here that tells you how.

Two habits run through all of it:

- **Look it up, do not remember it.** Almost every field here has been wrong at
  least once because somebody wrote down what they expected to be true.
- **Absent beats guessed.** Every field that can be unknown is allowed to be
  unknown. A blank is a fact a reader can act on; an invented value is not.

---

## 0. Decide whether to carry it at all

Do this first — it is cheap and it stops work on a workload that must be
rejected. If any of these hold, the workload goes in `catalog/excluded.libsonnet`
with the matching reason from the published vocabulary and a URL, **not** into
`workloads/`:

| reason | check |
| --- | --- |
| `licence-forbids-saas` | BUSL, SSPL, Elastic, Commons Clause, "you may not offer this as a service" |
| `upstream-sells-hosting` | the project sells its own hosting — carrying it competes with the people who wrote it |
| `upstream-archived` | the repository is archived or the project is dead |
| `no-published-source` | no source anywhere, or source that does not build the published image |
| `undeployable` | needs something a cluster cannot give it |

The build **fails** on a reason outside that vocabulary, so a new kind of
rejection is a deliberate decision, not a free-text note.

Also check early, because it is the most common late surprise: **does the image
actually exist and still get pulled?** 13 pins were already dead the first time
the catalogue was booted end to end.

```shell
crane manifest <image>:<tag> >/dev/null && echo ok
```

---

## 1. The files

One directory per workload — and it is an independently released unit, so the
name must never be `library` or `catalog` (tag-prefix collision; the release
discover job fails on it).

```text
workloads/<name>/
  <stage>.libsonnet     one file per STAGE (see §2)
  <stage>.image         the stage's default image, pinned by DIGEST
  version.txt           the literal text `dev` — CI overwrites it at release
  README.md             prose above the marker; the section below it is generated
```

- **`<stage>.image` is where the image reference lives, once.** Renovate watches
  that path. Pin `tag@sha256:…`: a tag says which version, only a digest says
  which bits.
- **`version.txt` is committed as `dev`** and read with
  `importstr './version.txt'`. It is a data file, licensed through `REUSE.toml`,
  and deliberately outside the `*.libsonnet` globs so no gate treats it as a
  stage.
- Every file needs an SPDX header or a `REUSE.toml` entry. `nix develop --command
  reuse lint` is the check.

---

## 2. Getting the stages right

A stage is an **ordered, gated install phase of one application** — apply it,
wait for it to go healthy, then the next. Stages are **not** environment tiers,
and most workloads need exactly one. Do not manufacture ordering an application
does not have.

A stage is `function(params)` returning a **composable app**: a base kind with
sensible defaults and **no exposure**. The consumer adds `+ kurly.expose.*`.

Every stage must:

- take a **`name`** parameter, and everything it renders must follow it — a
  namespace holds two copies only if their object names differ
- take a **`storageClass`** parameter if it renders a PVC, or use `kurly.store`
  so one can be composed
- accept **`podLabels` / `podAnnotations`** and the other pod features. A
  hand-authored workload that renders plain manifests must *reject* composed
  features loudly, or the feature silently does nothing
- survive `kurly.mirror` — every image it renders, including an initContainer's
  or a sidecar's, must follow onto a private registry

`check-tests` enforces all of the above per stage. Run it before anything else:

```shell
nix develop --command check-tests
```

### What booting the whole catalogue taught about images

The recurring reasons a workload renders perfectly and still will not run.
Check these first when a pod misbehaves:

- an init that drops privileges (s6-overlay, su-exec, gosu, anything that chowns
  a volume) needs `rootUser + allowPrivilegeEscalation + keepCapabilities`
- an app that writes beside its own code needs a `scratch` at that path
- a Service named after the workload makes Kubernetes inject `<APP>_PORT` as a
  `tcp://` URL, which apps read as their listen port — `kurly.disableServiceLinks`
- the port the stage declares must be the port the image actually binds
- a probe that follows a redirect, or hits a path answering 403/404, kills the
  pod forever — probe by connection where the app validates Host or needs auth
- a slow first start (migrations, asset builds, plugin relinking) needs
  `kurly.startupProbe`, not a longer liveness delay

---

## 3. The catalogue entry

In `catalog/annotations.libsonnet`. **`category` is mandatory** — the build
refuses a workload without one, from: `admin`, `application`, `cache`,
`database`, `identity`, `messaging`, `networking`, `observability`, `search`,
`storage`, `tool`.

Hand-annotated, because none of it is derivable:

- **`summary`** — for somebody deciding **how to run it**. Mechanics belong here.
- **`description`** — ONE sentence for somebody deciding whether they **want**
  it. No mechanics, no marketing, never opens with the software's own name, ≤160
  chars. The build enforces all of that.
- **`name`** — the software's own name, or absent. `org.opencontainers.image.title`
  holds taglines and base images as often as a product name, and a wrong display
  name is worse than none because nobody can tell by looking.
- **`upstream.repo`** / **`homepage`**
- **`requires`** — a LIST of `{ kind, required }` from the closed vocabulary
  `database`, `cache`, `objectStorage`, `broker`. A list, not a map: bigcapital
  needs a MySQL *and* a MongoDB.
- **`secretKeys`** per stage — the keys the Secret must hold and how to mint
  each: `password`, `hex`, `base64`, `base64url`, `literal`, `postgresUrl`,
  `redisUrl`, `mysqlUrl`, `external`. kurly authors no Secret itself.

**If the stage reads a Secret whose contents cannot be generated** — an
`objstore.yml`, a Dex config, an app signing key — declare no `secretKeys` and
add the stage to the exact set named in `catalog.jsonnet`'s assert, with the
reason. Do not invent a generator for a document a person has to write.

Then regenerate and check:

```shell
nix develop --command gen-readme        # splices the generated README section
nix develop --command check-catalog     # regenerates derived data, fails on drift
```

### What you do NOT write

These are derived by rendering the stage and will appear on their own. Never
hand-maintain them, and if one looks wrong the stage is wrong:

`storage.pvcs` · `posture` · `scaling` · `pss` · `profile` · `secrets` ·
`clusterScoped` · `runs` · `declaredRequests` · the database `engine`

---

## 4. What to look up online

Network-bound, so these run on demand or on a schedule — never in the per-PR
gate. Run them for a new workload and commit what they produce.

| what | how | notes |
| --- | --- | --- |
| image architectures | `gen-architectures` | keeps an amd64-only image off an arm64 node |
| image labels → licence, source, homepage | `gen-upstream` | takes `WORKLOADS=…` for a subset |
| signature | `gen-signatures` | only `signedByUpstream` is worth a badge |
| licence is real SPDX | `check-catalog` (offline, uses `gen-spdx`) | an unknown label is dropped and named; an unknown *annotation* fails the build |
| **trademark policy** | `hack/trademark-probe.sh` | see below |

**Trademark** is the one that needs judgement, not just a command. The probe
finds *candidates*; whether a page answers the question is a reading job.

1. Run the probe — it follows links the homepage already carries and asks the
   forge for the repository's real file list.
2. If the mark is held by a **foundation** (Apache, Linux Foundation, LF
   Projects, Eclipse, OpenJS, Wikimedia), the project links one policy rather
   than restating it. Check whose mark it is before concluding there is none.
3. Read what you find. Record `posture` + the `policy` URL it was read from —
   both required. `unaddressed` means somebody read it and it does not say;
   **absent means nobody looked**, and neither is permission.
4. **Never derive a posture from the licence.** The code grant and the mark
   routinely disagree.

---

## 5. Proving it runs

Rendering is not running. In order:

```shell
nix develop --command gen-smoke                      # generates a scenario per workload
nix develop --command bash hack/smoke/scenario-<id>.sh   # boot it on kind
```

A generated scenario is marker-guarded, so a hand-written one is never
clobbered. If the app needs a deployment-specific value it cannot have a sane
default for (its own public URL), put it in `hack/smoke/extra.json` rather than
baking a wrong default into the stage.

Then the two evidence ledgers, which are **dated records of what actually
happened**, never claims:

- `catalog/e2e-verified.libsonnet` — booted on a live cluster and reached
  readiness. This is what earns the `e2e` tier.
- `catalog/delivered-verified.libsonnet` — went the whole way through Flux →
  JaaS → stageset, written by `hack/smoke/deep-run.sh`. A separate **axis**, not
  a rung: a stage can boot from a checkout and still fail here (a wrong import
  path renders locally and not from the image).

Finally, the full gate — what CI runs, so green here is green there:

```shell
nix develop --command verify
```

---

## 6. Who to tell, and what to ask them

**The portal** (`metio.cloud`) — after any change to what `catalog.json`
publishes. It pins the catalogue by digest, so tell it:

- the new digest, and what is in it
- any **new field**, whether it is derived or hand-annotated, and what absent
  means for it
- any **new value in an enum it switches on** — always ask before adding one.
  Its readers fail closed on values they cannot interpret, so an unannounced
  value silently becomes the safe default and the field quietly does nothing.

**The IG BvC** (`gitlab.opencode.de/ig-bvc/policy-entwicklung/richtlinien-umsetzung-kyverno`)
— only when a workload exposes something about the *policies* rather than about
itself: a rule that fires on a name rather than a fact, a control the Pod
Security Standards take back and the policies do not. Search their issues first;
there is usually an open one, and a comment on it beats a fresh proposal.

**A workload's maintainers** — only for `consent`, and only in person. It records
what a maintainer *asked* of anyone hosting their software commercially. It
cannot be swept, derived, or inferred: absence means nobody asked, and there is
deliberately no `offered` status because carrying one would assert a conversation
that never happened. Honouring such a request is a **policy choice**, not a legal
obligation — every licence here permits commercial hosting.

---

## Quick sequence

```shell
# 0. reject early
crane manifest <image>:<tag> >/dev/null

# 1-3. author, annotate, regenerate
nix develop --command check-tests
nix develop --command gen-readme
nix develop --command check-catalog

# 4. the network-bound facts
nix develop --command gen-architectures
WORKLOADS=<name> nix develop --command gen-upstream
bash hack/trademark-probe.sh          # then READ what it finds

# 5. prove it runs, then the full gate
nix develop --command gen-smoke
nix develop --command bash hack/smoke/scenario-<name>.sh
nix develop --command verify
```
