// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The kurly assembler: an Alpine component that starts from a published workload,
// composes kurly `+` features onto it, and emits the Jsonnet snippet and JaaS
// manifests to deploy it. It reads the catalog (catalog/catalog.json, injected
// by the layout) and never talks to a server — every output is generated in the
// browser from the catalog and the user's choices.

document.addEventListener('alpine:init', () => {
  Alpine.data('assembler', () => ({
    catalog: { workloads: [], features: [], expose: [], security: [] },
    selected: null, // { workload, stage }
    workloadArgs: {}, // arg name -> binding
    composed: [], // { key, section, feature, args: {name -> binding} }
    namespace: '',

    init() {
      const el = document.getElementById('kurly-catalog');
      if (el) this.catalog = JSON.parse(el.textContent);
    },

    // A binding records where a parameter's value comes from: its default
    // (omitted from the snippet), a hard-coded literal, or a pass-through TLA.
    newBinding(arg) {
      return {
        mode: arg.required ? 'value' : 'default',
        value: arg.example != null ? String(arg.example) : '',
        tla: arg.name,
      };
    },

    // ---- selection -------------------------------------------------------
    get kind() {
      return this.selected ? this.selected.stage.kind : null;
    },
    select(workload, stage) {
      this.selected = { workload, stage };
      this.namespace = workload.id;
      this.workloadArgs = {};
      (stage.args || []).forEach((a) => {
        this.workloadArgs[a.name] = this.newBinding(a);
      });
      this.composed = [];
    },
    reset() {
      this.selected = null;
    },

    // ---- palette ---------------------------------------------------------
    // Features whose advisory `kinds` include the workload's kind, bucketed by
    // their palette group.
    get featureGroups() {
      const groups = {};
      this.catalog.features
        .filter((f) => (f.kinds || []).includes(this.kind))
        .forEach((f) => {
          (groups[f.group] = groups[f.group] || []).push(f);
        });
      return Object.keys(groups)
        .sort()
        .map((g) => ({ group: g, items: groups[g] }));
    },
    // Exposure recipes are legal only on a kind that ships a Service.
    get exposeItems() {
      const hasService = this.hasService(this.kind);
      return hasService ? this.catalog.expose : [];
    },
    get securityItems() {
      return this.catalog.security;
    },
    hasService(kind) {
      const k = this.catalog.kinds.find((x) => x.id === kind);
      return k ? !!k.hasService : false;
    },

    // Blocks composing a second member of an exclusion group (e.g. two
    // exposures) — the same constraint kurly asserts at render time.
    blockedReason(section, feature) {
      if (feature.exclusiveGroup) {
        const clash = this.composed.find(
          (c) => c.feature.exclusiveGroup === feature.exclusiveGroup,
        );
        if (clash) {
          return `one ${feature.exclusiveGroup} per workload (already have ${clash.feature.id})`;
        }
      }
      return null;
    },
    add(section, feature) {
      if (this.blockedReason(section, feature)) return;
      const args = {};
      (feature.args || []).forEach((a) => {
        args[a.name] = this.newBinding(a);
      });
      this.composed.push({ key: `${section}:${feature.id}:${Date.now()}`, section, feature, args });
    },
    remove(idx) {
      this.composed.splice(idx, 1);
    },

    // ---- value formatting ------------------------------------------------
    // Renders a hard-coded value as a Jsonnet literal for its type. Array and
    // object values are passed through verbatim so a user can type a Jsonnet
    // literal (e.g. ['a', 'b'] or { cpu: '100m' }).
    fmtValue(type, raw) {
      const v = raw == null ? '' : String(raw);
      switch (type) {
        case 'int':
          return v.trim();
        case 'bool':
          return v === 'true' || v === true ? 'true' : 'false';
        case 'array':
        case 'object':
          return v.trim();
        default:
          return `'${v.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
      }
    },

    // The expression for each provided argument, ALWAYS named.
    //
    // A positional call binds by order, which would make the catalog's argument
    // order part of the contract: list two arguments in an order the function
    // does not declare and every value lands in the wrong parameter, producing a
    // snippet that renders and means something else. Jsonnet has no types to
    // catch it, so it surfaces only where a schema happens to disagree — and not
    // at all between two neighbouring strings. Named calls make order irrelevant.
    argExprs(argSpecs, bindings) {
      const out = [];
      (argSpecs || []).forEach((a) => {
        const b = bindings[a.name];
        if (!b || (b.mode !== 'value' && b.mode !== 'tla')) return;
        const expr = b.mode === 'tla' ? b.tla : this.fmtValue(a.type, b.value);
        out.push(`${a.name}=${expr}`);
      });
      return out;
    },

    // The `+ kurly.…` term for a composed feature. Security profiles are mixin
    // objects (no call); features and exposure recipes are functions.
    callExpr(item) {
      if (item.section === 'security') return `kurly.security.${item.feature.id}`;
      const prefix = item.section === 'expose' ? 'kurly.expose.' : 'kurly.';
      return `${prefix}${item.feature.id}(${this.argExprs(item.feature.args, item.args).join(', ')})`;
    },

    // Every parameter bound as a pass-through, de-duplicated by TLA name.
    get tlas() {
      const seen = new Map();
      const collect = (specs, bindings) => {
        (specs || []).forEach((a) => {
          const b = bindings[a.name];
          if (b && b.mode === 'tla' && !seen.has(b.tla)) {
            seen.set(b.tla, { name: b.tla, arg: a });
          }
        });
      };
      if (this.selected) collect(this.selected.stage.args, this.workloadArgs);
      this.composed.forEach((c) => collect(c.feature.args, c.args));
      return Array.from(seen.values());
    },

    // ---- helpers ---------------------------------------------------------
    // A Jsonnet identifier for a workload id. Ids are DNS-1123 names, which allow
    // hyphens and a leading digit; an identifier allows neither, so `cal-com`
    // becomes `cal_com` and `2fauth` becomes `_2fauth`.
    ident(id) {
      const safe = id.replace(/[^A-Za-z0-9_]/g, '_');
      return /^[0-9]/.test(safe) ? `_${safe}` : safe;
    },

    // The name a stage's objects carry — its `name` parameter's default, which is
    // what a ready check has to look for.
    stageName(w, s) {
      const arg = (s.args || []).find((a) => a.name === 'name');
      return arg && arg.default != null ? String(arg.default) : `${w.id}-${s.id}`;
    },

    // The controller a stage rolls out, so a StageSet can gate on it. A stage
    // whose kind is a custom resource is reconciled by its operator into objects
    // this cannot name, so it carries no check rather than a wrong one.
    stageCheck(kind) {
      const controllers = {
        http: { apiVersion: 'apps/v1', kind: 'Deployment' },
        worker: { apiVersion: 'apps/v1', kind: 'Deployment' },
        stateful: { apiVersion: 'apps/v1', kind: 'StatefulSet' },
        daemon: { apiVersion: 'apps/v1', kind: 'DaemonSet' },
        cron: { apiVersion: 'batch/v1', kind: 'CronJob' },
      };
      return controllers[kind] || null;
    },

    // The snippet for ONE stage. The stage the visitor configured carries their
    // parameters and composed features; every other stage of the same workload
    // renders with its defaults, so the wiring deploys the whole workload rather
    // than the one piece that happened to be on screen.
    snippetFor(w, s) {
      const configured = this.selected && this.selected.stage === s;
      const alias = this.ident(w.id);
      const header = [
        "local kurly = import 'github.com/metio/kurly/main.libsonnet';",
        `local ${alias} = import '${s.importPath}';`,
        '',
      ];
      const args = configured ? this.argExprs(s.args, this.workloadArgs).join(', ') : '';
      const terms = [`${alias}(${args})`];
      if (configured) this.composed.forEach((c) => terms.push(`+ ${this.callExpr(c)}`));
      const body = `kurly.list(\n    ${terms.join('\n    ')}\n  )`;

      const tlas = configured ? this.tlas : [];
      if (tlas.length === 0) return `${header.join('\n')}${body}`;
      const params = tlas
        .map((t) =>
          t.arg.default != null ? `${t.name}=${this.fmtValue(t.arg.type, t.arg.default)}` : t.name,
        )
        .join(', ');
      return `${header.join('\n')}function(${params})\n  ${body}`;
    },

    // ---- outputs ---------------------------------------------------------
    get snippet() {
      if (!this.selected) return '';
      return this.snippetFor(this.selected.workload, this.selected.stage);
    },

    // The full JaaS wiring: the two source images (kurly recipes + this
    // workload's source), a JsonnetLibrary for each, one JsonnetSnippet per stage
    // of the workload, and the StageSet that deploys them in order.
    //
    // A StageSet exists to run ORDERED, GATED stages, so every stage the workload
    // declares gets its own snippet and its own entry: a multi-stage workload
    // whose StageSet named one stage would deploy one part of itself, and stages
    // all pointing at a single artifact would each apply the whole workload,
    // leaving the gating with nothing to order.
    get jaas() {
      if (!this.selected) return '';
      const w = this.selected.workload;
      const s = this.selected.stage;
      const ns = this.namespace || w.id;
      const workloadDir = s.importPath.replace(/\/[^/]+$/, ''); // drop the file name
      const ociPath = workloadDir.replace(/^github\.com\//, ''); // metio/kurly/workloads/tik
      const libName = `kurly-${w.id}`;
      const stages = w.stages || [s];

      // A TLA is one list entry keyed by name. Values bind as strings, which is
      // what every parameter here wants — a snippet taking a number parses it
      // itself, so nothing needs `code: true`. Only the configured stage carries
      // them; the rest render with their defaults.
      const tlaLines = this.tlas.map((t) => {
        const example = t.arg.example != null ? t.arg.example : t.arg.default != null ? t.arg.default : '';
        return `    - name: ${t.name}\n      value: "${example}"`;
      });
      const tlaBlock = tlaLines.length ? `  tlas:\n${tlaLines.join('\n')}\n` : '';

      const snippets = stages.map((st) => {
        const name = this.stageName(w, st);
        const indented = this.snippetFor(w, st)
          .split('\n')
          .map((l) => (l ? `      ${l}` : ''))
          .join('\n');
        const tlas = st === s ? tlaBlock : '';
        return `apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ${name}, namespace: ${ns} }
spec:
  serviceAccountName: ${w.id}-renderer
  files:
    main.jsonnet: |
${indented}
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: ${libName}, importPath: ${workloadDir} }
${tlas}`;
      });

      const stageEntries = stages.map((st) => {
        const name = this.stageName(w, st);
        const check = this.stageCheck(st.kind);
        const readyChecks = check
          ? `
      readyChecks:
        checks:
          - apiVersion: ${check.apiVersion}
            kind: ${check.kind}
            name: ${name}`
          : '';
        return `    - name: ${st.id}
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: ${name}${readyChecks}`;
      });

      return `apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: ${ns} }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: ${libName}, namespace: ${ns} }
spec: { interval: 12h, url: oci://ghcr.io/${ociPath}, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ${ns} }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: ${libName}, namespace: ${ns} }
spec: { sourceRef: { kind: OCIRepository, name: ${libName} } }
---
${snippets.join('---\n')}---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ${w.id}, namespace: ${ns} }
spec:
  serviceAccountName: ${w.id}-deployer
  rollbackOnFailure: true
  stages:
${stageEntries.join('\n')}`;
    },

    async copy(text) {
      try {
        await navigator.clipboard.writeText(text);
      } catch (e) {
        /* clipboard unavailable — the text is selectable in the block */
      }
    },
  }));
});
