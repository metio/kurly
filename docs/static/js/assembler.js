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

    // ---- outputs ---------------------------------------------------------
    get snippet() {
      if (!this.selected) return '';
      const w = this.selected.workload;
      const s = this.selected.stage;
      const header = [
        "local kurly = import 'github.com/metio/kurly/main.libsonnet';",
        `local ${w.id} = import '${s.importPath}';`,
        '',
      ];
      const terms = [`${w.id}(${this.argExprs(s.args, this.workloadArgs).join(', ')})`];
      this.composed.forEach((c) => terms.push(`+ ${this.callExpr(c)}`));
      const body = `kurly.list(\n    ${terms.join('\n    ')}\n  )`;

      const tlas = this.tlas;
      if (tlas.length === 0) return `${header.join('\n')}${body}`;
      const params = tlas
        .map((t) =>
          t.arg.default != null ? `${t.name}=${this.fmtValue(t.arg.type, t.arg.default)}` : t.name,
        )
        .join(', ');
      return `${header.join('\n')}function(${params})\n  ${body}`;
    },

    // The full JaaS wiring: the two source images (kurly recipes + this
    // workload's source), a JsonnetLibrary for each, the JsonnetSnippet carrying
    // the composed snippet, and the StageSet that deploys it.
    get jaas() {
      if (!this.selected) return '';
      const w = this.selected.workload;
      const s = this.selected.stage;
      const ns = this.namespace || w.id;
      const workloadDir = s.importPath.replace(/\/[^/]+$/, ''); // drop the file name
      const ociPath = workloadDir.replace(/^github\.com\//, ''); // metio/kurly/workloads/tik
      const libName = `kurly-${w.id}`;
      const indented = this.snippet
        .split('\n')
        .map((l) => (l ? `      ${l}` : ''))
        .join('\n');
      // A TLA is one list entry keyed by name. Values bind as strings, which is
      // what every parameter here wants — a snippet taking a number parses it
      // itself, so nothing needs `code: true`.
      const tlaLines = this.tlas.map((t) => {
        const example = t.arg.example != null ? t.arg.example : t.arg.default != null ? t.arg.default : '';
        return `    - name: ${t.name}\n      value: "${example}"`;
      });
      const tlaBlock = tlaLines.length ? `  tlas:\n${tlaLines.join('\n')}\n` : '';
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
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ${w.id}, namespace: ${ns} }
spec:
  serviceAccountName: ${w.id}-renderer
  files:
    main.jsonnet: |
${indented}
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: ${libName}, importPath: ${workloadDir} }
${tlaBlock}---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ${w.id}, namespace: ${ns} }
spec:
  serviceAccountName: ${w.id}-deployer
  rollbackOnFailure: true
  stages:
    - name: ${s.id}
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: ${w.id}
      readyChecks:
        checks:
          - apiVersion: apps/v1
            kind: Deployment
            name: ${w.id}`;
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
